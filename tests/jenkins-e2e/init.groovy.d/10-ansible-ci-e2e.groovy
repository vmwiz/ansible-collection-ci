// Configuration du banc : bibliotheque globale "ansible-ci" (depot git local), agent "runner-1"
// (label ansible-runner), jobs de test. Rejoue a chaque demarrage (idempotent).
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import jenkins.plugins.git.GitSCMSource
import jenkins.plugins.git.traits.BranchDiscoveryTrait
import jenkins.plugins.git.traits.TagDiscoveryTrait
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher

def j = Jenkins.get()
j.setNumExecutors(0)
JenkinsLocationConfiguration.get().setUrl('http://jenkins:8080/')

// Bibliotheque globale = de confiance (hors sandbox). v1 = branche mobile, v1.0.0 = tag.
def src = new GitSCMSource('file:///repos/ansible-ci.git')
src.setTraits([new BranchDiscoveryTrait(), new TagDiscoveryTrait()])
def lib = new LibraryConfiguration('ansible-ci', new SCMSourceRetriever(src))
lib.setDefaultVersion('v1')
lib.setImplicit(false)
lib.setAllowVersionOverride(true)
GlobalLibraries.get().setLibraries([lib])

// Agent inbound websocket, label ansible-runner
if (j.getNode('runner-1') == null) {
    def agent = new DumbSlave('runner-1', '/home/ci/agent', new JNLPLauncher())
    agent.setNumExecutors(8)
    agent.setLabelString('ansible-runner')
    j.addNode(agent)
}
new File('/var/jenkins_home/shared').mkdirs()
new File('/var/jenkins_home/shared/runner-1.secret').text = j.getComputer('runner-1').getJnlpMac()

// Jobs
def recreate = { String name, def definition ->
    j.getItem(name)?.delete()
    WorkflowJob job = j.createProject(WorkflowJob, name)
    job.setDefinition(definition)
    job.save()
}
def scm = new GitSCM(GitSCM.createRepoList('file:///repos/corp.demo.git', null), [new BranchSpec('*/main')], null, null, [])
recreate('corp-demo', new CpsScmFlowDefinition(scm, 'Jenkinsfile'))
recreate('corp-demo-ee', new CpsScmFlowDefinition(scm, 'Jenkinsfile.ee'))
recreate('corp-demo-ee-bad', new CpsScmFlowDefinition(scm, 'Jenkinsfile.ee-bad'))
new File('/usr/share/jenkins/ref/e2e-jobs').eachFileMatch(~/.*\.groovy/) { f ->
    recreate(f.name - '.groovy', new CpsFlowDefinition(f.text, true))   // sandbox : comme un Jenkinsfile
}
j.save()
println 'ansible-ci e2e : configuration appliquee'
