allprojects {
    repositories {
        // Google's Maven Central mirror first: Maven Central's own CDN
        // redirects some large jars (e.g. the Kotlin compiler) to GitHub
        // releases, whose downloads intermittently time out (HTTP 504).
        maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
