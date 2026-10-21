// Verification : la directive declarative `matrix` refuse des valeurs d'axe non litterales.
def cores = ['2.20', '2.21']
pipeline {
    agent none
    stages {
        stage('matrice') {
            matrix {
                axes { axis { name 'CORE'; values cores } }
                stages { stage('x') { steps { echo "core ${CORE}" } } }
            }
        }
    }
}
