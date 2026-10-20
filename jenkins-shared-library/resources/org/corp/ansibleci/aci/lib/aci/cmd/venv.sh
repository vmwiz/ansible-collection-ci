# shellcheck shell=bash
# aide:   venv [outils]   cree/reutilise le venv (core|lint|docs|import|molecule|security) d'ACI_CORE et affiche son chemin
main() { aci_venv "${1:-core}"; }
