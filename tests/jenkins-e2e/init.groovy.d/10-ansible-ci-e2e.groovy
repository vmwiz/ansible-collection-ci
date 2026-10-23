// Bench setup on top of infra/jenkins/jcasc.yaml: two inbound agents and the test jobs.
// Replayed at every start (idempotent).
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher

def j = Jenkins.get()
j.setNumExecutors(0)
JenkinsLocationConfiguration.get().setUrl('http://jenkins:8080/')

// runner-1 stands in for the 'ansible-runner' pod, builder-1 for the ansible-builder Podman VM
[['runner-1', 'ansible-runner', 6, '/home/ci/agent'], ['builder-1', 'ansible-builder', 2, '/tmp/jk/builder']].each { a ->
    if (j.getNode(a[0]) == null) {
        def agent = new DumbSlave(a[0], a[3], new JNLPLauncher())
        agent.setNumExecutors(a[2])
        agent.setLabelString(a[1])
        j.addNode(agent)
    }
    new File('/var/jenkins_home/shared').mkdirs()
    new File("/var/jenkins_home/shared/${a[0]}.secret").text = j.getComputer(a[0]).getJnlpMac()
}

// corp-demo: full example collection (units, integration, Molecule), Jenkinsfile @v2 (moving tag)
// corp-demo-lite: same collection without tests/unit, tests/integration, extensions/molecule, pinned @v2.0.0
['corp-demo', 'corp-demo-lite'].each { name ->
    j.getItem(name)?.delete()
    def scm = new GitSCM(GitSCM.createRepoList("file:///repos/${name}.git", null), [new BranchSpec('*/main')], null, null, [])
    WorkflowJob job = j.createProject(WorkflowJob, name)
    job.setDefinition(new CpsScmFlowDefinition(scm, 'Jenkinsfile'))
    job.save()
}
j.save()
println 'ansible-ci e2e: bench configured'
