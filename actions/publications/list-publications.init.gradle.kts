import org.gradle.api.publish.PublishingExtension
import org.gradle.api.publish.maven.MavenPublication

// Adds a task to every project that publishes with maven-publish. It prints one line per
// publication: where it lands in a Maven repository, its artifact and version, and the task that
// uploads it to the repository named by -PkotlinWorkflow.repository.
allprojects {
    val projectPath = buildTreePath.removeSuffix(":")
    plugins.withId("maven-publish") {
        tasks.register("kotlinWorkflowPublications") {
            val repository = providers.gradleProperty("kotlinWorkflow.repository").get()
            doLast {
                val publishing = project.extensions.getByType(PublishingExtension::class.java)
                publishing.publications.withType(MavenPublication::class.java).forEach { publication ->
                    val directory = publication.groupId.replace('.', '/') + "/" + publication.artifactId
                    val name = publication.name.replaceFirstChar { it.uppercase() }
                    val task = "$projectPath:publish${name}PublicationTo${repository}Repository"
                    println("KW|$directory|${publication.artifactId}|${publication.version}|$task")
                }
            }
        }
    }
}
