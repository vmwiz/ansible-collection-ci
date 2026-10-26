#!/usr/bin/env bash
# Creates a stand-alone git repository with the example collection at its root, ready to be a Jenkins job
# that loads the library dynamically (Jenkinsfile.dev becomes the Jenkinsfile).
# Usage: tools/export-collection.sh <dest-dir> [library-git-url] [library-ref]
#   library-git-url  replaces the placeholder remote of Jenkinsfile.dev (default: keep the placeholder)
#   library-ref      branch, tag or commit of the library to load (default: master)
# Then: cd <dest-dir> && git remote add origin <collection-repo-url> && git push -u origin main
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:?usage: tools/export-collection.sh <dest-dir> [library-git-url] [library-ref]}
url=${2:-}; ref=${3:-master}
[ ! -e "$dest" ] || { echo "ERROR: $dest already exists" >&2; exit 1; }
cp -r "$root/example-collection/corp.demo" "$dest"
cd "$dest"
rm -rf dist reports tests/output
mv Jenkinsfile.dev Jenkinsfile
sed -i "s#identifier: 'ansible-ci@master'#identifier: 'ansible-ci@$ref'#" Jenkinsfile
[ -z "$url" ] || sed -i "s#remote: 'https://gitlab.corp.local/ci/ansible-collection-ci.git'#remote: '$url'#" Jenkinsfile
git init -q -b main && git add -A && git -c user.name="${GIT_AUTHOR_NAME:-ansible-ci}" -c user.email="${GIT_AUTHOR_EMAIL:-ci@corp.local}" commit -qm "corp.demo test collection (library ansible-ci@$ref)"
echo "test collection repository ready: $dest (Jenkinsfile loads ansible-ci@$ref)"
