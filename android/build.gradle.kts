allprojects {
    repositories {
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
    val subproject = this
    
    // Set build directory
    val newSubprojectBuildDir: Directory = newBuildDir.dir(subproject.name)
    subproject.layout.buildDirectory.value(newSubprojectBuildDir)

    // Fix for "Namespace not specified" or incorrect "package" attribute in older plugins
    subproject.afterEvaluate {
        val extension = subproject.extensions.findByName("android")
        if (extension is com.android.build.gradle.BaseExtension) {
            // Force removal of package attribute by ensuring namespace is set in Gradle
            if (extension.namespace == null) {
                extension.namespace = when (subproject.name) {
                    "telephony" -> "com.shounakmulay.telephony"
                    "flutter_sms_inbox" -> "com.example.flutter_sms_inbox"
                    "flutter_windowmanager" -> "io.adaptant.labs.flutter_windowmanager"
                    else -> "in.softbridgelabs.text.${subproject.name.replace("-", "_")}"
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
