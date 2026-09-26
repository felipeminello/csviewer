#!/usr/bin/env bash
# Gera o build do CSViewer para macOS e envia para o App Store Connect.
#
# Uso:
#   ASC_ISSUER_ID=<issuer> tool/appstore.sh [--build-name X.Y.Z] [--build-number N] [--export-only]
#
# Sem --build-name/--build-number, usa a versão do pubspec.yaml (version: X.Y.Z+N).
# Cada envio precisa de um build number maior que o anterior.
# --export-only gera o .pkg assinado em build/macos/export, sem enviar.
#
# Variáveis de ambiente:
#   ASC_ISSUER_ID  obrigatória — App Store Connect → Usuários e Acesso → Integrações
#   ASC_KEY_ID     padrão HLTPKC2CY4
#   ASC_KEY_PATH   padrão ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=5DJSZLRUXA
ASC_KEY_ID=${ASC_KEY_ID:-HLTPKC2CY4}
ASC_KEY_PATH=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}

build_args=()
export_only=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --build-name) build_args+=("--build-name=$2"); shift 2 ;;
    --build-number) build_args+=("--build-number=$2"); shift 2 ;;
    --export-only) export_only=true; shift ;;
    -h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
  esac
done

: "${ASC_ISSUER_ID:?defina ASC_ISSUER_ID (App Store Connect → Usuários e Acesso → Integrações)}"
[[ -f $ASC_KEY_PATH ]] || { echo "Chave não encontrada: $ASC_KEY_PATH" >&2; exit 1; }

archive=build/macos/CSViewer.xcarchive
export_dir=build/macos/export
auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

# Só gera a config do Xcode (versão e build number); o Dart é compilado pelo archive.
flutter build macos --release --config-only ${build_args[@]+"${build_args[@]}"}

# O projeto assina com "-" (ad-hoc) para que `flutter build macos` funcione sem
# certificado, inclusive no CI. A assinatura com o time fica só no archive.
rm -rf "$archive" "$export_dir"
xcodebuild -quiet \
  -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination generic/platform=macOS \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Apple Development" \
  "${auth[@]}" archive

export_options=macos/ExportOptions.plist
if $export_only; then
  export_options=build/macos/ExportOptions-export.plist
  cp macos/ExportOptions.plist "$export_options"
  plutil -replace destination -string export "$export_options"
fi

# Reassina com o certificado de distribuição e, com destination=upload, envia.
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_dir" \
  "${auth[@]}"

version=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive/Info.plist")
if $export_only; then
  echo "Pacote $version ($build) gerado em $export_dir/"
else
  echo "Versão $version ($build) enviada. Aparece no App Store Connect depois do processamento."
fi
