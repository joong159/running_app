// 1. 기존에 있던 allprojects { repositories { ... } } 블록을 완전히 삭제했습니다.
// 이 설정은 이미 settings.gradle.kts에 들어가 있어서 여기서 중복되면 에러가 납니다.

// 빌드 디렉토리 설정 (현중님의 기존 로직 유지)
val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // 서브프로젝트 평가 의존성 유지
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}