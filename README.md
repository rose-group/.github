.github


- maven-build.yml: 创建 tag，触发 deploy、site、release 任务
- release-by-manual.yml：基于 main 分支，更新版本号，手动触发 deploy 任务，创建 tag，并创建 Release 和 milestone