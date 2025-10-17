#!/usr/bin/env bash
set -euo pipefail
clear
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
MOBILE_DIR=$(dirname "${SCRIPT_DIR}")

# app.keychain の設定
KEYCHAIN_NAME=app.keychain
KEYCHAIN_PATH=~/Library/Keychains/$KEYCHAIN_NAME-db
KEYCHAIN_PASS=1212
P12_DEV_PATH=${SCRIPT_DIR}/certs/Mobile_Development.p12
P12_DEV_PASS=zaq12wsX
P12_DIS_PATH=${SCRIPT_DIR}/certs/Mobile_Distribution.p12
P12_DIS_PASS=zaq12wsX

# develop.keychain作成
if [[ -f "$KEYCHAIN_PATH" ]]; then
  security default-keychain -s ~/Library/Keychains/login.keychain-db
  security delete-keychain ${KEYCHAIN_NAME}
fi
security create-keychain -p ${KEYCHAIN_PASS} ${KEYCHAIN_NAME}
security set-keychain-settings -lut 21600 ${KEYCHAIN_PATH}
security unlock-keychain -p ${KEYCHAIN_PASS} ${KEYCHAIN_PATH}

# develop.keychainをデフォルトに設定
security list-keychains -s ${KEYCHAIN_PATH} ~/Library/Keychains/login.keychain-db
security default-keychain -s ${KEYCHAIN_PATH}

# 証明書のインストール/Applications/Xcode.app/Contents/_CodeSignature
security import "${P12_DIS_PATH}" -k ${KEYCHAIN_PATH} -P ${P12_DIS_PASS} -A -T /usr/bin/codesign
security import "${P12_DEV_PATH}" -k ${KEYCHAIN_PATH} -P ${P12_DEV_PASS} -A -T /usr/bin/codesign

# partition設定
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k ${KEYCHAIN_PASS} ${KEYCHAIN_PATH}
security find-identity -v -p codesigning ${KEYCHAIN_PATH}

# プロビジョニングプロファイルのインストール
rm -rf ~/Library/MobileDevice/Provisioning\ Profiles
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp certs/*.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/
ls -la ~/Library/MobileDevice/Provisioning\ Profiles/

# reactive-nativeおよびiosの依頼関係のインストール
cd "${MOBILE_DIR}"
npm install && bundle install
cd "${SCRIPT_DIR}"
pod install
xattr -w com.apple.xcode.CreatedByBuildSystem true build

APP_PREFIX="C-SAAF"
APP_NAME="Mobile"
PROJ="${APP_NAME}.xcodeproj"
TODAY=$(date +"%Y%m%d")

# 各種ID、プロファイル名の設定
MATRIX=(
  "Mobile,Debug,cap,8H26AJ8X5P,org.reactjs.native.example.Mobile.cap,MobileCapDebug,Apple Development"
  "Mobile,Debug,pa,8H26AJ8X5P,org.reactjs.native.example.Mobile.pa,MobilePaDebug,Apple Development"
  "Mobile,Debug,honban,8H26AJ8X5P,org.reactjs.native.example.Mobile.honban,MobileHonbanDebug,Apple Development"
  "Mobile,Release,cap,8H26AJ8X5P,org.reactjs.native.example.Mobile.cap,MobileCapRelease,Apple Distribution"
  "Mobile,Release,pa,8H26AJ8X5P,org.reactjs.native.example.Mobile.pa,MobilePaRelease,Apple Distribution"
  "Mobile,Release,honban,8H26AJ8X5P,org.reactjs.native.example.Mobile.honban,MobileHonbanRelease,Apple Distribution"
)

cd "${SCRIPT_DIR}"
rm -rf output
mkdir -p output
pod install

for ROW in "${MATRIX[@]}"; do
  echo "${ROW}"
  IFS=',' read -r SCHEME CONFIG TARGET TEAM_ID DOMAIN SPECIFIER SIGN <<< "${ROW}"

  cd "${MOBILE_DIR}"
  DEV_MODE=$([ "${CONFIG}" == "Debug" ])
  npx react-native bundle --entry-file index.js --platform ios --dev "${DEV_MODE}" --bundle-output ios/main.jsbundle --assets-dest ios

  cd "${SCRIPT_DIR}"
  MARKETING_VERSION=$(xcodebuild -project "${PROJ}" -scheme "${SCHEME}" -configuration "${CONFIG}" -showBuildSettings | awk '/MARKETING_VERSION/ {print $3; exit}')
  CURRENT_PROJECT_VERSION=$(xcodebuild -project "${PROJ}" -scheme "${SCHEME}" -configuration "${CONFIG}" -showBuildSettings | awk '/CURRENT_PROJECT_VERSION/ {print $3; exit}')

  xcodebuild clean archive \
      -workspace "${APP_NAME}.xcworkspace" \
      -scheme "${SCHEME}" \
      -configuration "${CONFIG}" \
      -archivePath "build/${SPECIFIER}" \
      -destination 'generic/platform=iOS' \
      MARKETING_VERSION="${MARKETING_VERSION}" \
      CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION}" \
      PRODUCT_BUNDLE_IDENTIFIER="${DOMAIN}" \
      DEVELOPMENT_TEAM="${TEAM_ID}" \
      CODE_SIGN_STYLE="Manual" \
      PROVISIONING_PROFILE_SPECIFIER="${SPECIFIER}" \
      CODE_SIGN_IDENTITY="${SIGN}"

  xcodebuild -exportArchive \
        -archivePath "build/${SPECIFIER}.xcarchive" \
        -exportOptionsPlist "ExportOptions/ExportOptions-${CONFIG}.plist" \
        -exportPath build/ipa

  OUT_PUT_FILE_NAME="${APP_PREFIX}-${APP_NAME}-${CONFIG}-${TARGET}-${MARKETING_VERSION}-${CURRENT_PROJECT_VERSION}-${TODAY}.ipa"

  mv "build/ipa/${APP_NAME}.ipa" "output/${OUT_PUT_FILE_NAME}"
done



# keychainの回復
security default-keychain -s ~/Library/Keychains/login.keychain-db
security delete-keychain ${KEYCHAIN_NAME}