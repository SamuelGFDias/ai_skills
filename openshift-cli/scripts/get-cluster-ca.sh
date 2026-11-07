#!/usr/bin/env bash
# get-cluster-ca.sh — extrai e salva a CA raiz (autoassinada) apresentada pelo API server
# de um cluster OpenShift, para uso com `oc login --certificate-authority=<arquivo>`
# em vez de `--insecure-skip-tls-verify`. Ver docs/certificado-tls.md nesta skill.
#
# Uso: get-cluster-ca.sh <host> [porta] [arquivo-saida]
#   host   : ex. api.ses-rj-hml.saude.rj.gov.br
#   porta  : default 6443
#   saida  : default ~/.config/openshift-ca/<primeiro-label-do-host>-ca.crt

set -euo pipefail

HOST="${1:?Uso: get-cluster-ca.sh <host> [porta] [arquivo-saida]}"
PORT="${2:-6443}"
OUT="${3:-$HOME/.config/openshift-ca/${HOST%%.*}-ca.crt}"

mkdir -p "$(dirname "$OUT")"

TMP_CHAIN="$(mktemp)"
trap 'rm -f "$TMP_CHAIN" "${TMP_CHAIN}.part-"*' EXIT

echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "$TMP_CHAIN"

if [ ! -s "$TMP_CHAIN" ]; then
  echo "ERRO: não recebi certificado nenhum de $HOST:$PORT (rede/VPN/host incorreto?)" >&2
  exit 1
fi

csplit -s -z -f "${TMP_CHAIN}.part-" "$TMP_CHAIN" '/-----BEGIN CERTIFICATE-----/' '{*}'

FOUND=0
for f in "${TMP_CHAIN}.part-"*; do
  subj=$(openssl x509 -in "$f" -noout -subject 2>/dev/null || true)
  iss=$(openssl x509 -in "$f" -noout -issuer 2>/dev/null || true)
  # CA raiz = certificado autoassinado (issuer == subject)
  if [ -n "$subj" ] && [ "$subj" = "${iss/issuer=/subject=}" ]; then
    cp "$f" "$OUT"
    FOUND=1
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "ERRO: não encontrei um certificado autoassinado na cadeia de $HOST:$PORT" >&2
  exit 1
fi

echo "CA salva em: $OUT"
echo "Use com: oc login --certificate-authority=\"$OUT\" --server=https://$HOST:$PORT --token=..."
