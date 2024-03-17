#!/bin/bash

URL="$1"
VENDOR_URL="$2"
GITHUB_ENV="$3"
GITHUB_WORKSPACE="$4"

origin_os_version=$(echo ${URL} | cut -d"/" -f4)                 # 移植的 OS 版本号, 例: OS1.0.6.0.UNACNXM
origin_version=$(echo ${origin_os_version} | sed 's/OS1/V816/g') # 移植的实际版本号, 例: V816.0.6.0.UNACNXM
vendor_os_version=$(echo ${VENDOR_URL} | cut -d"/" -f4)          # 底包的 OS 版本号, 例: OS1.0.32.0.UNCCNXM
vendor_version=$(echo ${vendor_os_version} | sed 's/OS1/V816/g') # 底包的实际版本号, 例: V816.0.32.0.UNCCNXM
origin_zip_name=$(echo ${VENDOR_URL} | cut -d"/" -f5)
android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1)
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)

magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
ksud="$GITHUB_WORKSPACE"/tools/KernelSU/ksud
lkm="$GITHUB_WORKSPACE"/tools/KernelSU/android14-6.1_kernelsu.ko
a7z="$GITHUB_WORKSPACE"/tools/7zzs
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

device=houji

Start_Time() {
  Start_ns=$(date +'%s%N')
}

End_Time() {
  # 小时、分钟、秒、毫秒、纳秒
  local h min s ms ns End_ns time
  End_ns=$(date +'%s%N')
  time=$(expr $End_ns - $Start_ns)
  [[ -z "$time" ]] && return 0
  ns=${time:0-9}
  s=${time%$ns}
  if [[ $s -ge 10800 ]]; then
    echo -e "\e[1;34m - 本次$1用时: 少于100毫秒 \e[0m"
  elif [[ $s -ge 3600 ]]; then
    ms=$(expr $ns / 1000000)
    h=$(expr $s / 3600)
    h=$(expr $s % 3600)
    if [[ $s -ge 60 ]]; then
      min=$(expr $s / 60)
      s=$(expr $s % 60)
    fi
    echo -e "\e[1;34m - 本次$1用时: $h小时$min分$s秒$ms毫秒 \e[0m"
  elif [[ $s -ge 60 ]]; then
    ms=$(expr $ns / 1000000)
    min=$(expr $s / 60)
    s=$(expr $s % 60)
    echo -e "\e[1;34m - 本次$1用时: $min分$s秒$ms毫秒 \e[0m"
  elif [[ -n $s ]]; then
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $s秒$ms毫秒 \e[0m"
  else
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $ms毫秒 \e[0m"
  fi
}

### 系统包下载
echo -e "\e[1;31m - 开始下载系统包 \e[0m"
echo -e "\e[1;33m - 开始下载移植包 \e[0m"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$URL"
End_Time 下载移植包
Start_Time
echo -e "\e[1;33m - 开始下载底包 \e[0m"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$VENDOR_URL"
End_Time 下载底包
### 系统包下载结束

### 解包
sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools
echo -e "\e[1;31m - 开始解压系统包 \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip
ZIP_NAME_Third_Party=$(echo ${URL} | cut -d"/" -f5)
echo -e "\e[1;33m - 开始解压移植包 \e[0m"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party -r -o"$GITHUB_WORKSPACE"/Third_Party >/dev/null
rm -rf "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party
End_Time 解压移植包
echo -e "\e[1;33m - 开始解压底包 \e[0m"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${origin_zip_name} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${origin_zip_name}
End_Time 解压底包
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
echo -e "\e[1;31m - 开始解底包payload \e[0m"
Start_Time
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/"${device}"/payload.bin -X system,system_ext,product -e -T0
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
End_Time 解底包payload
echo -e "\e[1;31m - 开始分解底包image \e[0m"
for i in mi_ext odm system_dlkm vendor vendor_dlkm; do
  echo -e "\e[1;33m - 正在分解底包: $i.img \e[0m"
  Start_Time
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
  End_Time 分解$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
cd "$GITHUB_WORKSPACE"/images
echo -e "\e[1;31m - 开始解移植包payload \e[0m"
$payload_extract -s -o "$GITHUB_WORKSPACE"/images/ -i "$GITHUB_WORKSPACE"/Third_Party/payload.bin -X product,system,system_ext -T0
End_Time 解移植包payload
echo -e "\e[1;31m - 开始分解移植包image \e[0m"
for i in product system system_ext; do
  echo -e "\e[1;33m - 正在分解移植包: $i \e[0m"
  Start_Time
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/images/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  End_Time 分解$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束

### 写入变量
# 构建日期
echo "build_time=$build_time" >>$GITHUB_ENV
# 移植包版本
echo "origin_os_version=$origin_os_version" >>$GITHUB_ENV
# 底包版本
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
# 移植包安全补丁
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo "security_patch=$security_patch" >>$GITHUB_ENV
# 移植包基线版本
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
line=$(grep "ro.system.build.fingerprint=" $system_build_prop)
base_line=$(echo "$line" | awk -F: '{split($2,a,"/"); print a[2]}')
echo "base_line=$base_line" >>$GITHUB_ENV
### 写入变量结束

### 功能修复
echo -e "\e[1;31m - 开始功能修复 \e[0m"
Start_Time
# 添加 KernelSU 支持（可选择）
echo -e "\e[1;31m - 添加 KernelSU 支持（可选择） \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/init_boot
cd "$GITHUB_WORKSPACE"/init_boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot.img "$GITHUB_WORKSPACE"/init_boot
$ksud boot-patch -b "$GITHUB_WORKSPACE"/init_boot/init_boot.img -m $lkm --magiskboot $magiskboot
mv -f "$GITHUB_WORKSPACE"/init_boot/kernelsu_boot*.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot-kernelsu.img
rm -rf "$GITHUB_WORKSPACE"/init_boot
# 替换 vendor_boot 的 fstab
echo -e "\e[1;31m - 替换 Vendor Boot 的 fstab \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1
fi
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  cp -f $ramdisk ramdisk.cpio
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 vendor 的 fstab
echo -e "\e[1;31m - 替换 vendor 的 fstab \e[0m"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom
# 替换 Product 的叠加层
echo -e "\e[1;31m - 替换 product 的叠加层 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
# 替换 device_features 文件
echo -e "\e[1;31m - 替换 device_features 文件 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/device_features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/
# 替换 displayconfig 文件
echo -e "\e[1;31m - 替换 displayconfig 文件 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/
# 统一 build.prop
echo -e "\e[1;31m - 统一 build.prop \e[0m"
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=YuKongA/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
for build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop'); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$build_prop"
  sudo sed -i 's/'"${origin_os_version}"'/'"${vendor_os_version}"'/g' "$build_prop"
  sudo sed -i 's/'"${origin_version}"'/'"${vendor_version}"'/g' "$build_prop"
  sudo sed -i 's/persist.device_config.mglru_native.lru_gen_config=[^*]*/persist.device_config.mglru_native.lru_gen_config=all/' "$build_prop"
done
for build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$build_prop"
  sudo sed -i 's/ro.mi.os.version.incremental=[^*]*/ro.mi.os.version.incremental='"$origin_os_version"'/' "$build_prop"
done
# 精简部分应用
echo -e "\e[1;31m - 精简部分应用 \e[0m"
for files in MIGalleryLockscreen MIUIDriveMode MIUIDuokanReader MIUIGameCenter MIUINewHome MIUIYoupin MIUIHuanJi MIUIMiDrive MIUIVirtualSim ThirdAppAssistant XMRemoteController MIUIVipAccount MiuiScanner Xinre SmartHome MiShop MiRadio MIUICompass MediaEditor BaiduIME iflytek.inputmethod MIService MIUIEmail MIUIVideo MIUIMusicT; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${files}*")
  if [[ $appsui != "" ]]; then
    echo -e "\e[1;33m - 找到精简目录: $appsui \e[0m"
    sudo rm -rf $appsui
  fi
done
# 分辨率修改
echo -e "\e[1;31m - 分辨率修改 \e[0m"
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if [ $(grep -c "$FIND_STR" $FIND_FILE) -ne '0' ]; then
    Character_present=true
    echo -e "\e[1;33m - 找到指定字符: $2 \e[0m"
  else
    Character_present=false
    echo -e "\e[1;33m - !未找到指定字符: $2 \e[0m"
  fi
}
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop persist.miui.density_v2
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=480/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a persist.miui.density_v2=480' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
# 替换相机
echo -e "\e[1;31m - 替换相机 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.1 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.2 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.3 >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/
# 替换相机标定
echo -e "\e[1;31m - 替换相机标定 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 占位毒瘤和广告
echo -e "\e[1;31m - 占位毒瘤和广告 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/AnalyticsCore.apk "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 替换完美图标
echo -e "\e[1;31m - 替换完美图标 \e[0m"
cd ${GITHUB_WORKSPACE}
git clone https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons --depth 1
for pkg in $(ls "$GITHUB_WORKSPACE"/images/product/media/theme/miui_mod_icons/dynamic/); do
  if [[ -d ${GITHUB_WORKSPACE}/icons/icons/$pkg ]]; then
    rm -rf ${GITHUB_WORKSPACE}/icons/icons/$pkg
  fi
done
rm -rf ${GITHUB_WORKSPACE}/icons/icons/com.xiaomi.scanner
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip
rm -rf "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
mkdir -p ${GITHUB_WORKSPACE}/icons/res
mv ${GITHUB_WORKSPACE}/icons/icons ${GITHUB_WORKSPACE}/icons/res/drawable-xxhdpi
cd ${GITHUB_WORKSPACE}/icons
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip res
cd ${GITHUB_WORKSPACE}/icons/themes/Hyper/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd ${GITHUB_WORKSPACE}/icons/themes/common/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
rm -rf ${GITHUB_WORKSPACE}/icons
cd ${GITHUB_WORKSPACE}
# 常规修改
echo -e "\e[1;31m - 常规修改 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
# 修复 init 崩溃
echo -e "\e[1;31m - 修复 init 崩溃 \e[0m"
sudo sed -i "/start qti-testscripts/d" "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/init/hw/init.qcom.rc
# 内置 TWRP
echo -e "\e[1;31m - 内置 TWRP \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/recovery.zip -d "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
# 添加刷机脚本
echo -e "\e[1;31m - 添加刷机脚本 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
echo -e "\e[1;31m - 移除 Android 签名校验 \e[0m"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $apktool_jar d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "\e[1;33m - ${i}  修改成功 \e[0m"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $apktool_jar b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# 对齐系统更新获取更新路径
echo -e "\e[1;31m - 对齐系统更新获取更新路径 \e[0m"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sed 's/^\.\///' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=houji/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=houji_pre/' "$mod_device_build"
  fi
done
# 替换更改文件/删除多余文件
echo -e "\e[1;31m - 替换更改文件/删除多余文件 \e[0m"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "\e[1;31m - 开始打包 IMAGE \e[0m"
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  echo -e "\e[1;31m - 正在生成: $i \e[0m"
  sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
  sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
  Start_Time
  sudo $erofs_mkfs -zlz4hc,9 -T 1230768000 --mount-point /$i --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts "$GITHUB_WORKSPACE"/images/$i.img "$GITHUB_WORKSPACE"/images/$i >/dev/null
  End_Time 打包erofs
  eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
  sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
Start_Time
$lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:8321499136 --metadata-slots 3 --group qti_dynamic_partitions_a:8321499136 --group qti_dynamic_partitions_b:8321499136 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
End_Time 打包super
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
### 生成 super.img 结束

### 输出卡刷包
echo -e "\e[1;31m - 开始生成卡刷包 \e[0m"
echo -e "\e[1;31m - 开始压缩super.zst \e[0m"
Start_Time
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -12 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
End_Time 压缩super.zst
# 生成卡刷包
echo -e "\e[1;31m - 生成卡刷包 \e[0m"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/miui_${device}_${origin_os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 压缩卡刷包
# 定制 ROM 包名
echo -e "\e[1;31m - 定制 ROM 包名 \e[0m"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_${device}_${origin_os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="miui_${device}_${origin_os_version}_${zip_md5}_${android_version}.0_YuKongA.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/miui_${device}_${origin_os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name="${rom_name}"" >>$GITHUB_ENV

### 输出卡刷包结束