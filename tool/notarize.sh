#!/usr/bin/env bash
# Assina o CSViewer.app com o Developer ID, notariza na Apple e gera o zip para
# distribuir fora da App Store. Sem isso o macOS bloqueia o app baixado com
# "A Apple não pôde verificar se o item CSViewer está livre de malware".
#
# Uso:
#   ASC_ISSUER_ID=<issuer> ASC_KEY_ID=<key> TEAM_ID=<team> tool/notarize.sh [--app caminho/CSViewer.app] [--zip saida.zip]
#
# Rode depois de `flutter build macos --release`. Precisa do certificado
# "Developer ID Application" do time em algum keychain da lista de busca.
#
# Variáveis de ambiente:
#   ASC_ISSUER_ID  obrigatória — App Store Connect → Usuários e Acesso → Integrações
#   ASC_KEY_ID     obrigatória — mesma tela, coluna "ID da chave"
#   TEAM_ID        obrigatória — developer.apple.com/account → Membership details
#   ASC_KEY_PATH   padrão ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8

set -euo pipefail

cd "$(dirname "$0")/.."

app=build/macos/Build/Products/Release/CSViewer.app
zip=build/macos/CSViewer-macos.zip
while [[ $# -gt 0 ]]; do
  case $1 in
    --app) app=$2; shift 2 ;;
    --zip) zip=$2; shift 2 ;;
    -h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
  esac
done

: "${ASC_ISSUER_ID:?defina ASC_ISSUER_ID (App Store Connect → Usuários e Acesso → Integrações)}"
: "${ASC_KEY_ID:?defina ASC_KEY_ID (App Store Connect → Usuários e Acesso → Integrações, coluna \"ID da chave\")}"
: "${TEAM_ID:?defina TEAM_ID (developer.apple.com/account → Membership details)}"
ASC_KEY_PATH=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}
[[ -f $ASC_KEY_PATH ]] || { echo "Chave não encontrada: $ASC_KEY_PATH" >&2; exit 1; }
[[ -d $app ]] || { echo "App não encontrado: $app (rode flutter build macos --release)" >&2; exit 1; }

# Pelo hash, para não depender do nome exato no certificado.
identity=$(security find-identity -v -p codesigning |
  awk -v team="($TEAM_ID)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')
[[ -n $identity ]] || {
  echo "Certificado \"Developer ID Application\" do time $TEAM_ID não encontrado no keychain." >&2
  echo "Crie em Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
}

# O flutter build sai com assinatura ad-hoc e com get-task-allow, que a
# notarização recusa. Reassina de dentro para fora, com hardened runtime
# (exigido pela notarização) e as entitlements de release.
for bundle in "$app"/Contents/Resources/*.bundle; do
  # Resource bundles dos plugins: só têm o PrivacyInfo.xcprivacy, a
  # assinatura do app já os cobre (mesmo tratamento do tool/appstore.sh).
  if codesign -d "$bundle" 2>/dev/null; then
    codesign --remove-signature "$bundle"
  fi
done
for item in "$app"/Contents/Frameworks/*; do
  codesign --force --timestamp --options runtime --sign "$identity" "$item"
done
codesign --force --timestamp --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$identity" "$app"
codesign --verify --strict --deep "$app"

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
result=$(xcrun notarytool submit "$zip" --wait --output-format json \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
status=$(plutil -extract status raw -o - - <<<"$result")
if [[ $status != Accepted ]]; then
  echo "Notarização recusada ($status):" >&2
  xcrun notarytool log "$(plutil -extract id raw -o - - <<<"$result")" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2
  exit 1
fi

# Grava o ticket no app, para o Gatekeeper aceitar mesmo sem internet, e
# refaz o zip com o app já "grampeado".
xcrun stapler staple "$app"
spctl --assess --type execute "$app"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
echo "App assinado e notarizado: $zip"
