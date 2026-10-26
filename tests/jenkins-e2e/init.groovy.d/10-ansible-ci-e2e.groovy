// Bench setup, done the way an admin would in "Manage Jenkins":
// global library ansible-ci, Secret text credentials, two inbound agents, the test jobs.
// Replayed at every start (idempotent).
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.GitSCM
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher
import hudson.util.Secret
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import jenkins.plugins.git.GitSCMSource
import jenkins.plugins.git.traits.BranchDiscoveryTrait
import jenkins.plugins.git.traits.TagDiscoveryTrait
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever

def j = Jenkins.get()
j.setNumExecutors(0)
JenkinsLocationConfiguration.get().setUrl('http://jenkins:8080/')

// Manage Jenkins > System > Global Trusted Pipeline Libraries
def src = new GitSCMSource('file:///repos/ansible-ci.git')
src.setTraits([new BranchDiscoveryTrait(), new TagDiscoveryTrait()])
def lib = new LibraryConfiguration('ansible-ci', new SCMSourceRetriever(src))
lib.setDefaultVersion('v2')
lib.setAllowVersionOverride(true)
lib.setImplicit(false)
// run-e2e.sh DEV=1: no global library at all, the jobs load ansible-ci with the `library` step
GlobalLibraries.get().setLibraries(System.getenv('ACI_E2E_NO_GLOBAL_LIBRARY') ? [] : [lib])

// Manage Jenkins > Credentials: the two default IDs + the team IDs used by corp-demo-params / corp-demo-spotter
def store = SystemCredentialsProvider.getInstance().getStore()
['spotter-api-token', 'nexus-galaxy-hosted-token', 'bench-team-spotter', 'bench-team-galaxy'].each { id ->
    store.addCredentials(Domain.global(), new StringCredentialsImpl(CredentialsScope.GLOBAL, id, 'bench', Secret.fromString('bench')))
}
// read-only git credential referenced by Jenkinsfile.dev (unused by file:// but must resolve)
store.addCredentials(Domain.global(), new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, 'git-readonly', 'bench', 'bench', 'bench'))

// runner-1 stands in for the OpenShift pod (label used by the bench copy of the library),
// builder-1 for the ansible-builder Podman VM (both the default label and the one of corp-demo-params)
[['runner-1', 'ansible-runner', 6, '/home/ci/agent'], ['builder-1', 'ansible-builder podman-bench', 2, '/tmp/jk/builder']].each { a ->
    if (j.getNode(a[0]) == null) {
        def agent = new DumbSlave(a[0], a[3], new JNLPLauncher())
        agent.setNumExecutors(a[2])
        agent.setLabelString(a[1])
        j.addNode(agent)
    }
    new File('/var/jenkins_home/shared').mkdirs()
    new File("/var/jenkins_home/shared/${a[0]}.secret").text = j.getComputer(a[0]).getJnlpMac()
}

// one job per bench repository (see run-e2e.sh)
new File('/repos').eachFileMatch(~/corp-demo.*\.git/) { f ->
    String name = f.name - '.git'
    j.getItem(name)?.delete()
    def scm = new GitSCM(GitSCM.createRepoList("file:///repos/${f.name}", null), [new BranchSpec('*/main')], null, null, [])
    WorkflowJob job = j.createProject(WorkflowJob, name)
    job.setDefinition(new CpsScmFlowDefinition(scm, 'Jenkinsfile'))
    job.save()
}
j.save()
println 'ansible-ci e2e: bench configured'
