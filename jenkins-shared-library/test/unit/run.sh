#!/usr/bin/env bash
# Tests unitaires de Config.groovy avec le Groovy embarque par Jenkins (groovy-all 2.4.21 du jenkins.war),
# sans demarrer Jenkins.  JENKINS_IMAGE : image jenkins/jenkins (ou derivee) disponible localement.
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
engine=${ENGINE:-podman}
"$engine" run --rm --entrypoint sh -v "$here:/jsl:ro,z" -w /tmp "${JENKINS_IMAGE:-localhost/jk:test}" -c '
  set -e
  unzip -q -o /usr/share/jenkins/jenkins.war "WEB-INF/lib/groovy-all-*.jar" -d /tmp/w
  g=$(ls /tmp/w/WEB-INF/lib/groovy-all-*.jar); mkdir -p /tmp/out
  echo "groovy : $(basename "$g")"
  java -cp "$g" org.codehaus.groovy.tools.FileSystemCompiler -d /tmp/out \
    /jsl/test/unit/stubs/com/cloudbees/groovy/cps/NonCPS.groovy /jsl/src/org/corp/ansibleci/*.groovy
  java -cp "$g:/tmp/out" groovy.ui.GroovyMain /jsl/test/unit/ConfigTest.groovy \
    /jsl/resources/org/corp/ansibleci/aci/share/aci/python-map.txt'
