#!/usr/bin/env bash

# Constants
ARCH_REPO="https://gitlab.gcp.mercadona.com/frameworks/ios/archetypes/ios-archetype-swiftui"
ARCH_ASP_NAME="ios_archetype_swiftui"
ARCH_APP_ID="com.mercadona.archetypeswiftui"

# Storing execution path
execPath=$PWD

# Help function
helpFun(){
    echo -e "\n\033[1;1m[Usage]\n$0 -d <project_destination_path> -g <git_repo> -b <bundle_id> -v <archetype_version> -u <user_name> -e <user_email>\033[0m"
    echo -e "\n\033[1;1m[Parameters]\033[0m"
    echo -e "\033[1;1m\t-d\tDestination path for the new project. The archetype will be cloned into this path. E.g. '../NewApp'\033[0m"
    echo -e "\033[1;1m\t-g\tThe url of the GIT repository for this new app.\033[0m"
    echo -e "\033[1;1m\t-n\tName of the new app (Optional) E.g. 'NewApp'\033[0m"
    echo -e "\033[1;1m\t-b\tThe base bundle identifier. E.g. 'com.mercadona.archetype'\033[0m"
    echo -e "\033[1;1m\t-v\tThe base archetipe version (optional) E.g. '1.0.0'\n\033[0m"
    echo -e "\033[1;1m\t-u\tThe author name for git repo E.g. 'Example Name'\n\033[0m"
    echo -e "\033[1;1m\t-e\tThe author email for git repo E.g. 'example@mercadona.com'\n\033[0m"
    exit 1
}

# Check the step execution result
checkResult(){
    if [ $? != 0 ]
    then
    echo -e "\n\033[1;31m[✘] '$1' step FAILED \033[0m\n"
    exit 1
    fi
}

# Check the step execution result - Environment
optionalCheckResult(){
    if [ $? != 0 ]
    then
    echo -e "\n\033[1;31m[✘] '$1' step FAILED \033[0m\n"
    echo -e "\nContinuing...\n"
    fi
}

pause(){
    read -p "Press [Enter] key to continue..."
}

# Reading parameters
while getopts "d:g:n:b:v:u:e:" opt
do
case "$opt" in
d     ) projectPath="$OPTARG" ;;
g     ) gitRepo="$OPTARG" ;;
n    ) appName="$OPTARG" ;;
b     ) appId="$OPTARG" ;;
v    ) archVersion="$OPTARG" ;;
u    ) userName="$OPTARG" ;;
e    ) userEmail="$OPTARG" ;;
?     ) helpFun ;;
esac
done

# Print help in case any parameter is empty
if [ -z "$projectPath" ] || [ -z "$appId" ]
then
echo -e "\n\033[1;31m[✘] Required parameter(s) missing \033[0m\n";
helpFun
fi
echo -e "\n\033[1;34mInitializing Set Up... \033[0m"

# Getting app name
echo -e "\033[1;34m==> Getting name of the new app ...\033[0m\n"
if [ -z "$appName" ]; then
if [[ $gitRepo =~ ^.*\/(.*)\.git$ ]]; then
appName=${BASH_REMATCH[1]}
else
echo -e "\n\033[1;31m[✘] Not valid app name \033[0m\n"
echo -e "\n033[1;31m[✘] Step FAILED \033[0m\n"

exit 1
fi
fi
echo -e "\033[1;32m[✔] Found App name: $appName\n\033[0m"

# Cloning archetype
echo -e "\033[1;34m==> Cloning Mercadona FWK iOS Archetype Repository: '$ARCH_REPO' $archVersion...\033[0m"
if [ -z "$archVersion" ]
then
git clone $ARCH_REPO --branch master --depth 1 $projectPath
else
git clone $ARCH_REPO --branch $archVersion --depth 1 $projectPath
fi
checkResult "Cloning archetype repository"
echo -e "\033[1;32m[✔] Cloned successfully\n\033[0m"

# Moving to new app directory
echo -e "\033[1;34m==> Moving to path: '$execPath/$projectPath'...\033[0m"
cd $execPath/$projectPath
checkResult "Moving to app folder"
echo -e "\033[1;32m[✔] Moved successfully\\033[0m"

# Rename Main target directory
echo -e "\033[1;34m==> Renaming ${ARCH_ASP_NAME} directory to ${appName} ...\033[0m"
mv ${ARCH_ASP_NAME} ${appName}
checkResult "Renaming ${ARCH_ASP_NAME} directory"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Rename Tests target directory
echo -e "\033[1;34m==> Renaming ${ARCH_ASP_NAME}Tests directory to ${appName}Tests ...\033[0m"
mv ${ARCH_ASP_NAME}Tests ${appName}Tests
checkResult "Renaming ${ARCH_ASP_NAME}Tests directory"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Rename Entitlements files
echo -e "\033[1;34m==> Renaming Entitlements files ...\033[0m"
mv ${appName}/Environment/Debug.entitlements ${appName}/Environment/Debug.entitlements
mv ${appName}/Environment/Release.entitlements ${appName}/Environment/Release.entitlements
checkResult "Renaming Entitlements files"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Rename .xcodeproj bundle
echo -e "\033[1;34m==> Renaming ${ARCH_ASP_NAME}.xcodeproj to ${appName}.xcodeproj ...\033[0m"
mv ${ARCH_ASP_NAME}.xcodeproj ${appName}.xcodeproj
mv ${appName}.xcodeproj/xcshareddata/xcschemes/${ARCH_ASP_NAME}.xcscheme ${appName}.xcodeproj/xcshareddata/xcschemes/${appName}.xcscheme
mv "${appName}.xcodeproj/xcshareddata/xcschemes/${ARCH_ASP_NAME} Dev.xcscheme" "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Dev.xcscheme"
mv "${appName}.xcodeproj/xcshareddata/xcschemes/${ARCH_ASP_NAME} Itg.xcscheme" "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Itg.xcscheme"
mv "${appName}.xcodeproj/xcshareddata/xcschemes/${ARCH_ASP_NAME} Pre.xcscheme" "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Pre.xcscheme"
checkResult "Renaming ${ARCH_ASP_NAME}.xcodeproj"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Rename paths
echo -e "\033[1;34m==> Renaming project files ...\033[0m"
sed -i'' -e 's/${ARCH_ASP_NAME}/${appName}/g' ${appName}.xcodeproj/project.pbxproj
checkResult "Renaming project"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Update references in project.pbxproj
echo -e "\033[1;34m==> Updating references to ${ARCH_ASP_NAME} to ${appName} in project.pbxproj ...\033[0m"
cmd="s/${ARCH_ASP_NAME}/${appName}/g"
sed $cmd "${appName}.xcodeproj/project.pbxproj" > tmp; mv tmp "${appName}.xcodeproj/project.pbxproj"
sed $cmd "${appName}.xcodeproj/xcshareddata/xcschemes/${appName}.xcscheme" > tmp; mv tmp "${appName}.xcodeproj/xcshareddata/xcschemes/${appName}.xcscheme"
sed $cmd "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Dev.xcscheme" > tmp; mv tmp "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Dev.xcscheme"
sed $cmd "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Itg.xcscheme" > tmp; mv tmp "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Itg.xcscheme"
sed $cmd "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Pre.xcscheme" > tmp; mv tmp "${appName}.xcodeproj/xcshareddata/xcschemes/${appName} Pre.xcscheme"
checkResult "Changing old references"
echo -e "\033[1;32m[✔] Changed successfully\033[0m"

# Rename String Catalog files
echo -e "\033[1;34m==> Renaming String Catalog files ...\033[0m"
sed -i'' -e "s/${ARCH_ASP_NAME}/${appName}/g" "${appName}/Environment/Dev/InfoPlist.xcstrings"
sed -i'' -e "s/${ARCH_ASP_NAME}/${appName}/g" "${appName}/Environment/Itg/InfoPlist.xcstrings"
sed -i'' -e "s/${ARCH_ASP_NAME}/${appName}/g" "${appName}/Environment/Pro/InfoPlist.xcstrings"
sed -i'' -e "s/${ARCH_ASP_NAME}/${appName}/g" "${appName}/Environment/Pre/InfoPlist.xcstrings"
echo -e "\033[1;32m[✔] Renamed successfully\033[0m"

# Updating Software license in source files"
echo -e "\033[1;34m==> Updating Software license  ...\033[0m"
newAuthor="MERCADONA"
newOwnerCopyright="MERCADONA"
date=`date +%d\\\\/%m\\\\/%Y`
year=`date +%Y`
filepaths=$(find ./${appName}* -type f -name "*.swift")
filepathsSplitted=$(echo ${filepaths} | sed -E 's/( \.)/;./g')
OIFS=$IFS
IFS=';'
for i in $filepathsSplitted; do
sed "s/\/\/  ${ARCH_ASP_NAME}/\/\/  $appName/g" $i > tmp; mv tmp $i;
sed -E "s/Created by (.*) on [0-9]{2}\/[0-9]{2}\/[0-9]{4}/Created by ${newAuthor} on ${date}/g" $i > tmp; mv tmp $i
sed -E "s/Copyright © [0-9]{4} ([^\.]*)\./Copyright © ${year} $newOwnerCopyright./g" $i > tmp; mv tmp $i
done
IFS=$OIFS
echo -e "\033[1;32m[✔] Updated successfully\033[0m"

# Updating Tests imports in source files"
echo -e "\033[1;34m==> Updating Test imports  ...\033[0m"
archNameFormatted=${ARCH_ASP_NAME//"-"/"_"}
appNameFormatted=${appName//"-"/"_"}
filepaths=$(find ./${appName}Tests* -type f -name "*.swift")
filepathsSplitted=$(echo ${filepaths} | sed -E 's/( \.)/;./g')
OIFS=$IFS
IFS=';'
for i in $filepathsSplitted; do
sed "s/import ${archNameFormatted}/import ${appNameFormatted}/g" $i > tmp; mv tmp $i;
sed "s/@testable import ${archNameFormatted}/@testable import ${appNameFormatted}/g" $i > tmp; mv tmp $i;
done
IFS=$OIFS
echo -e "\033[1;32m[✔] Updated successfully\033[0m"

# Update Bundle ID
echo -e "\033[1;34m==> Updating Bundle ID ...\033[0m"
cmd="s/${ARCH_APP_ID}/${appId}/g"
sed $cmd ${appName}.xcodeproj/project.pbxproj > tmp; mv tmp ${appName}.xcodeproj/project.pbxproj
checkResult "Updating Bundle Id"
echo -e "\033[1;32m[✔] Updated successfully\033[0m"

# Empty CHANGELOG.md
echo -e "\033[1;34m==> Emptying CHANGELOG.md  ...\033[0m"
cat /dev/null > CHANGELOG.md
checkResult "Emptying CHANGELOG.md"
echo -e "\033[1;32m[✔] CHANGELOG.md changed successfully\033[0m"

# Delete old README
echo -e "\033[1;34m==> Removing README.md  ...\033[0m"
rm README.md;
checkResult "Removing README.md"
echo -e "\033[1;32m[✔] README.md removed successfully\033[0m"

# Removing .git directory
echo -e "\033[1;34m==> Removing .git directory\033[0m"
rm -rf .git
checkResult "Removing .git directory"
echo -e "\033[1;32m[✔] Removed successfully\033[0m"

# Preparing upload repository if online params are configured
if [ -n "$userName" ] && [ -n "$userEmail" ] && [ -n "$gitRepo" ]
then
echo -e "\033[1;34m==> Initalizing and configuring git repository\033[0m"
git init
git config user.name "${userName}"
git config user.email ${userEmail}
git remote add origin ${gitRepo}
git checkout -b master
git add .
git commit -m "Init project from script"
git push origin master --force
checkResult "Pushing to master"
git checkout -b develop
git push origin develop --force
checkResult "Pushing to develop"
echo -e "\033[1;32m[✔] Sources pushed to new app GIT repository successfully\033[0m"
fi

# Success
echo -e "\n\033[1;34m👍 Set Up DONE SUCCESSFULLY\033[0m"
