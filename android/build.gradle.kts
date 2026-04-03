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

    // Fix for "Namespace not specified" in older plugins
    subproject.plugins.whenPluginAdded {
        if (this is com.android.build.gradle.LibraryPlugin || this is com.android.build.gradle.AppPlugin) {
            val extension = subproject.extensions.findByName("android")
            if (extension is com.android.build.gradle.BaseExtension) {
                if (extension.namespace == null) {
                    extension.namespace = when (subproject.name) {
                        "telephony" -> "com.shounakmulay.telephony"
                        "flutter_sms_inbox" -> "com.example.flutter_sms_inbox"
                        else -> "in.softbridgelabs.text.${subproject.name.replace("-", "_")}"
                    }
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
