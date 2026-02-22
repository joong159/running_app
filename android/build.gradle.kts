// Project-level build.gradle.kts

allprojects {
    repositories {
        google()
        mavenCentral()
        // 네이버 지도 저장소 (최신 주소 및 Kotlin DSL 문법)
        maven {
            url = uri("https://naver.jfrog.io/artifactory/maven/")
        }
    }
}

// 빌드 디렉토리 설정 (기존에 작성하신 로직 유지)
val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // 추가: 모든 서브프로젝트에 대해 평가 의존성 설정
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}