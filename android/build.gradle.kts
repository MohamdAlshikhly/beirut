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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            // FIX 1 & 2: Extract original package and set as namespace, then strip package
            try {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    var content = manifestFile.readText()
                    
                    // 1. Find the package name
                    val packageMatcher = Regex("package=\"([^\"]*)\"").find(content)
                    val originalPackage = packageMatcher?.groupValues?.get(1)
                    
                    if (originalPackage != null) {
                        // 2. Set as namespace so R class is generated in the correct place
                        android.namespace = originalPackage
                        println("Syncing namespace for ${project.name} with $originalPackage")
                        
                        // 3. Strip package attribute to satisfy AGP 8.0+
                        val newContent = content.replace(Regex("package=\"[^\"]*\""), "")
                        if (content != newContent) {
                            manifestFile.writeText(newContent)
                            println("Successfully stripped package attribute from ${project.name}'s AndroidManifest.xml")
                        }
                    } else if (android.namespace == null) {
                        // Fallback if no package attribute found
                        val defaultNamespace = "com.github.mohamdalshikhly.${project.name.replace("-", ".")}"
                        android.namespace = defaultNamespace
                        println("Fixed missing namespace for ${project.name} using $defaultNamespace")
                    }
                }
            } catch (e: Exception) {
                println("Warning: Could not process manifest for ${project.name}: ${e.message}")
            }
        }
    }
}

// FIX 3: Enforce consistent JVM Target for Java and Kotlin tasks
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            
            // Handle both kotlinOptions (old way) and Kotlin DSL (new way)
            val kotlinNamespace = "org.jetbrains.kotlin.gradle.dsl.KotlinJvmOptions"
            val kotlinOptions = project.extensions.findByName("kotlinOptions")
            if (kotlinOptions != null) {
                try {
                    val jvmTargetField = kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                    jvmTargetField.invoke(kotlinOptions, "17")
                } catch (e: Exception) {
                    // Fallback to task-based if extension modification fails
                }
            }
        }
    }
    
    // Backup: task-based enforcement
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
