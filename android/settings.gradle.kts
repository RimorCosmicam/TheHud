pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Astronomy Engine, the sky's positions, as the iPhone app uses it.
        maven("https://jitpack.io") { content { includeGroup("com.github.cosinekitty") } }
    }
}

rootProject.name = "TheHud"
include(":app")
