#!/usr/bin/env bash


##########################################
# Download code from remote git repository
# Globals:
#    WORKSPACE
# Arguments:
#    repo_url
#    repo_name
#    branch
# Returns:
#    None
#########################################
function download_repository() {
    set -x # TEST
    git --version
    repo_url=$1
    repo_name=$2
    branch=$3
    clone_path=$4
    clone_code_dir="$WORKSPACE/${repo_name}"
    if [[ ! -z $clone_path && $clone_path != "0" && $clone_path != "null" ]];then
        clone_code_dir="$WORKSPACE/$clone_path"
    fi
    
    #   if [[ -d "$clone_code_dir" ]]; then
    #       echo "${clone_code_dir} is exist, remoe before checkout"
    #       rm -rf $clone_code_dir
    #   fi

    is_git_dir="${clone_code_dir}/.git"
    lock_git_file="${clone_code_dir}/.git/index.lock"
    lock_git_test_file="${clone_code_dir}/.git/refs/remotes/origin/qa_ceshi_bao.lock"
    if [[ -d $clone_code_dir ]] && [[ -d $is_git_dir ]] && [[ -f $lock_git_file ]];then
        rm -rf $lock_git_file
    fi
    if [[ -d $clone_code_dir ]] && [[ -d $is_git_dir ]] && [[ -f $lock_git_test_file ]];then
        rm -rf $lock_git_test_file
    fi
    if [[ -d $clone_code_dir ]] && [[ ! -d $is_git_dir ]];then
        cd $clone_code_dir
        git init
        git remote add origin "$repo_url"
        git fetch
        echo "$clone_code_dir is exist and not git ,git fetch"
    fi
    if [[ ! -d "$clone_code_dir" ]]; then
        echo "begin clone repo_url:${repo_url} branch:${branch} to dir:${clone_code_dir}"
        git clone -b "${branch}" --depth=1 "${repo_url}" "$clone_code_dir"
            cd "$clone_code_dir"
    else 
        cd "$clone_code_dir"
        git config remote.origin.url "${repo_url}"
        git remote prune origin
        git fetch origin
        git log --format=%B -n 1 "${branch}"
        git checkout -f "${branch}"
        if git show-ref --verify --quiet "refs/heads/${branch}"; then
          git branch -D "${branch}"
        fi
        git checkout -b "${branch}"
    fi
    git branch
}


function clone_main_code() {
    if [[ "$MAIN_GIT_URL" == "" ]];then
        echo "MAIN_GIT_URL is empty"
        echo "MAIN_GIT_URL=$MAIN_GIT_URL"
    fi
    if [[ "$MAIN_GIT_BRANCH" == "" ]];then
        echo "MAIN_GIT_BRANCH is empty"
        MAIN_GIT_BRANCH="master"
    fi
	TARGETCODEPATH="."
    repo_name=$(echo "${MAIN_GIT_URL}" | awk -F "/" '{print $2}' | awk -F "." '{print $1}')
    if [[ "$MAIN_CODE_TARGERT_PATH" == "" ]];then
        MAIN_CODE_TARGERT_PATH=${repo_name}
        export TARGETCODEPATH=${WORKSPACE}/${repo_name}
    elif [[ "$MAIN_CODE_TARGERT_PATH" == "." ]];then
        export TARGETCODEPATH=${WORKSPACE}
    else
        export TARGETCODEPATH=${WORKSPACE}/${MAIN_CODE_TARGERT_PATH}
    fi
    echo "clone code begin"
    echo "git_url=$MAIN_GIT_URL"
    echo "git_branch=$MAIN_GIT_BRANCH"
    echo "clone_path=$MAIN_CODE_TARGERT_PATH"
    download_repository "${MAIN_GIT_URL}" "${repo_name}" "${MAIN_GIT_BRANCH}" "${MAIN_CODE_TARGERT_PATH}"
    echo "clone code end"
}
function update_ssh_key(){
    if [[ "$CLOUD_BUILD_ID_RSA_KEY" != "" ]];then
		echo "set CLOUD_BUILD_ID_RSA_KEY"
        eval "$(ssh-agent -s)"
		#ssh-add <(echo "${id_rsa_key}")
		echo -e "$CLOUD_BUILD_ID_RSA_KEY" | ssh-add -
	else
	    if [[ $(uname -s) == "Darwin" ]]; then
            curl -s set_ssh.sh http://tosv.byted.org/obj/cloudbuildstatic/static/20191112/set_ssh_mac.sh| bash -s --
	    else
	        curl -s set_ssh.sh http://tosv.byted.org/obj/cloudbuildstatic/static/set_ssh.sh | bash -s --
	    fi
	fi
	if [[ "$GIT_ACCOUNT_NAME" != "" && "$GIT_ACCOUNT_EMAIL" != "" ]];then
		echo "set GIT_ACCOUNT_NAME && GIT_ACCOUNT_EMAIL"
    	git config --global user.name "${GIT_ACCOUNT_NAME}"
    	git config --global user.email "${GIT_ACCOUNT_EMAIL}"
	fi
}

# step 1 下载代码到本地
function clone_code() {
    update_ssh_key
    echo "WORKSPACE=$WORKSPACE"
    echo "clone code:$CLONE_CODE"
    echo "clone main code begin"
    clone_main_code
    echo "clone main code end"

    echo "clone code end"
}

# step 2 Gemfile安装插件
function bundler_env() {
    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
    echo "CLOUD_BUILD_INFO_LOG: 执行bundler更新模板"

    ## 0. 检查路径参数是不是绝对路径
    if [[ ! ${gemfile_path} =~ "${WORKSPACE}" && ${gemfile_path} != "" ]];then
        echo "CLOUD_BUILD_ERROR_LOG: 传入的 gemfile_path : ${gemfile_path} 参数非绝对路径，或者不在 $WORKSPACE 大路径以内，路径非法，程序退出"
        return 1
    fi

    ## 1. 输出ruby, bundler信息
    export PROJECT_PATH=${TARGETCODEPATH}
    cd ${PROJECT_PATH}
    echo "CLOUD_BUILD_INFO_LOG: PROJECT_PATH路径是："
    echo ${PROJECT_PATH}

    bundler --version

    ## 3. 依据Gemfile文件安装gems
    if [[ "${gemfile_path}" == "" ]]; then
        gemfile_path=${PROJECT_PATH}
    fi
    if [[ -f "${gemfile_path}/Gemfile" ]];then
        echo "CLOUD_BUILD_INFO_LOG: 成功在路径下找到Gemfile文件，寻径成功"
    else
        echo "CLOUD_BUILD_ERROR_LOG: 不存在 ${gemfile_path}/Gemfile 文件，路径错误，程序退出"
        return 1
    fi

    #touch Gemfile
    echo "CLOUD_BUILD_INFO_LOG: 当前Gemfile内容："
    cat Gemfile
    echo "" >> Gemfile # 加一个空行防止EOF问题

    rm -rf Gemfile.lock

    bundle install --path=`pwd` 2>&1

    cd ${WORKSPACE}
    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
}

# step 3 iOS证书安装
function cert_install() {
    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
    echo "CLOUD_BUILD_INFO_LOG: 执行证书安装模板"

    ## 1. 下载bigMac
    echo "CLOUD_BUILD_INFO_LOG: 查看证书下载路径"
    pwd
    bigMac_url="https://ios.bytedance.net/wlapi/tosDownload/iosbinary/bigmac_registry/release/bin/bigMac"
    curl -O ${bigMac_url}
    chmod +x bigMac

    # if [[ "${login_passwd}" == "******" ]]; then
    #     USERNAME=`whoami`
    #     export login_passwd=321321321ww${USERNAME}
    # fi

    if [[ ! -n "${login_passwd}" || "${login_passwd}" == "" ]]; then
        USERNAME="bytedance"
        # export login_passwd=321321321ww${USERNAME}
        
    fi

    if [[ ! -n "${cert_passwd}" || "${cert_passwd}" == "" ]]; then
        export cert_passwd="bytedance"
    fi
    echo "cert_url:${cert_url}"
    ## 2. 获取需要导入的证书，密码, 导入
    # cert_url, cert_passwd, login_passwd 由外部变量参数传入
    if [[ ! "${cert_url}" == "" ]]; then
        # curl -o cert.p12 ${cert_url}
        # cert.p12=${cert_url}
        # 导入证书
        # echo "cert_passwd:${cert_passwd}"
        security -v unlock-keychain -p ${login_passwd} "$HOME/Library/Keychains/login.keychain"
        ./bigMac utility install-p12 ${cert_url} ${cert_passwd} ${login_passwd} 2>&1
    else
        echo "CLOUD_BUILD_WARNING_LOG: 未传入证书, 忽略步骤"
    fi


    echo "CLOUD_BUILD_INFO_LOG: 查看处理完的路径"
    pwd
    ls


    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
}

# step 4 描述文件安装
function provision_install() {
    if [[ ! ${PROV_PATH} =~ "${WORKSPACE}" && ${PROV_PATH} != "" ]];then
        echo "CLOUD_BUILD_ERROR_LOG: 传入的 PROV_PATH : ${PROV_PATH} 参数非绝对路径，或者不在 $WORKSPACE 大路径以内，路径非法，程序退出"
        return 1
    fi

    ## 1. 下载安装
    if [[ "${PROV_PATH}" == "" ]]; then
        echo "CLOUD_BUILD_ERROR_LOG: 传入的 PROV_PATH 为空，无法安装工程中的描述文件，程序退出"
        return 1
    fi
    echo "PROV_PATH: $PROV_PATH"
    cd ${PROV_PATH}

    if ls *.mobileprovision 1> /dev/null 2>&1; then
        echo "CLOUD_BUILD_INFO_LOG: 文件夹中存在 mobileprovision 类型文件"
    else
        echo "CLOUD_BUILD_ERROR_LOG: 传入的 PROV_PATH 内没有任何 mobileprovision 类型文件，程序退出"
        return 1
    fi

    cd ~
    if [[ -d "Library/MobileDevice/Provisioning Profiles" ]]; then
        echo "CLOUD_BUILD_INFO_LOG: 存在对应Library/MobileDevice/Provisioning Profiles系统文件夹"
    else
        echo "CLOUD_BUILD_INFO_LOG: 创建对应Library/MobileDevice/Provisioning Profiles系统文件夹"
        mkdir -p Library/MobileDevice/Provisioning\ Profiles
    fi
    cd ${PROV_PATH}

    for file in *.*provision*; do
        uuid=`grep UUID -A1 -a "$file" | grep -io "[-A-F0-9]\{36\}"`
        extension="${file##*.}"
        echo "$file -> $uuid"
        echo "$extension"
        cp -f "$file" ~/Library/MobileDevice/Provisioning\ Profiles/"$uuid.$extension"
    done

    cd ${WORKSPACE}
}

# step 5 pod安装依赖
function pod_update() {
    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
    echo "CLOUD_BUILD_INFO_LOG: 执行pod依赖模板"

    ## 1. 进入Podfile 所在目录
    # 工程目录
    export PROJECT_PATH=${TARGETCODEPATH}
    cd ${PROJECT_PATH}

    # Podfile 文件所在目录
    if [[ "${POD_PATH}" == "" ]]; then
        POD_PATH=`dirname $(find ${PROJECT_PATH} -name 'Podfile' | awk '{ print length($0) " " $0; }' | sort -t ' ' -k 1 -n | awk 'NR==1{print}' | cut -d ' ' -f 2)`
    fi
    echo "Pod path: $POD_PATH"
    if [[ -f "${POD_PATH}/Podfile" ]];then
        echo "CLOUD_BUILD_INFO_LOG: 成功在路径下找到Podfile文件，寻径成功"
    else
        echo "CLOUD_BUILD_ERROR_LOG: 不存在 ${POD_PATH}/Podfile 文件，路径错误，程序退出"
        return 1
    fi
    export POD_PATH
    cd ${POD_PATH}

    ## 2.  打印 cocoapods 版本
    bundle exec pod --version

    ## 3. pod 依赖下载
        # 执行默认，同时对当前Podfile里面的源进行update以避免一些时序问题导致版本拉不到
    bundle exec pod update --verbose 2>&1

    cd ${WORKSPACE}
    echo "CLOUD_BUILD_INFO_LOG: ------------------------"
}



function realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

function inject_post_build_phase() {
    cat << EOF | bundle exec ruby
require 'xcodeproj'
def main()
  workspace_path = ENV["WORKSPACE_PATH"]
  # workspace
  workspace = Xcodeproj::Workspace.new_from_xcworkspace(workspace_path)
  # schemes
  schemes = workspace.schemes
  scheme_name = ENV["SCHEME"]
  project_path = schemes[scheme_name]
  scheme_path = "#{project_path}/xcshareddata/xcschemes/#{scheme_name}.xcscheme"
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  target_name = scheme.launch_action.buildable_product_runnable.buildable_reference.target_name
  target_uuid = scheme.launch_action.buildable_product_runnable.buildable_reference.target_uuid
  project = Xcodeproj::Project.open(project_path)
  found_target = project.native_targets.detect {|target| target.uuid == target_uuid}
  found_custom_build_phase = found_target.shell_script_build_phases.detect {|phase| phase.name == "bit-xcodebuild-export-env"}
  if found_custom_build_phase == nil
    found_custom_build_phase = found_target.new_shell_script_build_phase("bit-xcodebuild-export-env")
  end
  script = <<-EEV
set +e
if [ -z "\$BIT_UUID" ];then
    exit 0
fi
printenv > "${WORKSPACE_PATH}/../bit_xcodebuild_env"
exit 0
EEV
  found_custom_build_phase.shell_script = script
  project.save()
end

main
EOF
}
# step 6 xcodebuild
function xcodebuild() {

    TARGETCODEPATH=`realpath $TARGETCODEPATH`

    #clean
    cd "$cwd"
    rm -rf DerivedData
    [ -d results_bundle ] && rm -rf results_bundle
    [ -d results_bundle.xcresult ] && rm -rf results_bundle.xcresult
    [ -d build ] && rm -rf build
    mkdir build
    [ -d "${TARGETCODEPATH}/products" ] && rm -rf "${TARGETCODEPATH}/products"
    mkdir -p "${TARGETCODEPATH}/products"
    [ -f build_settings.xcconfig ] && rm -rf build_settings.xcconfig
    touch build_settings.xcconfig

    #common args
    echo cwd:"$cwd"
    cd "$cwd"
    if [ -z "$use_xcpretty" ];then
        export use_xcpretty="No"
    fi
    if [ -z "$sdk" ];then
        sdk="iphoneos"
    fi
    if [ -z "$build_action" ];then
        if [[ "$sdk" == "iphonesimulator" ]]; then
            build_action="build"
        else
            build_action="archive"
        fi
    fi
    if [ -z "$workspace_name" ];then
        workspace_name=$(ls -d *.xcworkspace)
    fi
    if [ -z "$xcodebuild_path" ];then
        xcodebuild_path="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
    fi

    build_setting_DEPLOYMENT_POSTPROCESSING="YES"

    #xcodebuild & args
    echo xcodebuild_path:"$xcodebuild_path"
    echo workspace_name:"$workspace_name"
    echo project_name:"$project_name"
    echo scheme:"$scheme"
    echo configuration:"$configuration"
    echo sdk:"$sdk"
    echo xcodebuild_extra:"$xcodebuild_extra"
    echo new_build_system:"$new_build_system"
    echo build_action:"$build_action"

    echo "CLOUD_BUILD_INFO_LOG: Xcode版本: "
    ${xcodebuild_path} -version

    #output
    cd "$cwd"
    export DERIVED_DATA_PATH=`realpath DerivedData`
    export XCRESULTS_BUNDLE_PATH=`realpath results_bundle`
    export XCARCHIVE_PATH=`realpath ./build/${scheme}.xcarchive`
    export SCHEME="$scheme"
    export CONFIGURATION="$configuration"
    export SDK="$sdk"
    if [ ! -z "$workspace_name" ];then
        export WORKSPACE_PATH=`realpath $workspace_name`
        inject_post_build_phase
    fi

    if [ ! -z "$workspace_name" ];then
        export WORKSPACE_PATH=`realpath $workspace_name`
    fi

    if [ ! -z "$project_name" ];then
        export PROJECT_PATH=`realpath $project_name`
    fi

    #pre build
    cd "$cwd"
    xcodebuild_command="-workspace"
    if [ ! -z "$workspace_name" ];then
        xcodebuild_command="${xcodebuild_command} `realpath ${workspace_name}`"
    else
        xcodebuild_command="-project"
        if [ ! -z "$project_name" ];then
            xcodebuild_command="${xcodebuild_command} `realpath ${project_name}`"
        else
            echo "error:unknow input arg workspace_name or project_name"
            return 1
        fi
    fi

    if [ ! -z "$scheme" ];then
        xcodebuild_command="${xcodebuild_command} -scheme ${scheme}"
    else
        echo "error:unknow input arg scheme"
        return 1
    fi

    if [ ! -z "$configuration" ];then
        xcodebuild_command="${xcodebuild_command} -configuration ${configuration}"
    else
        echo "error:unknow input arg configuration"
        return 1
    fi

    if [[ "$build_action" == "archive" ]];then
        xcodebuild_command="${xcodebuild_command} -archivePath ${XCARCHIVE_PATH}"
    fi

    echo "CLOUD_BUILD_INFO_LOG: DerivedPath放置在"
    echo ${DERIVED_DATA_PATH}
    xcodebuild_command="${xcodebuild_command} -derivedDataPath ${DERIVED_DATA_PATH}"
    xcodebuild_command="${xcodebuild_command} -xcconfig build_settings.xcconfig"
    xcodebuild_command="${xcodebuild_command} -resultBundlePath results_bundle"

    ## 模拟器为了简化业务方使用，自动拼接destination，如果有提供额外的信息的话可以自己复写需要的值
    if [[ "${xcodebuild_destination}" == "" ]]; then
        if [[ "$sdk" == "iphoneos" ]]; then
            xcodebuild_destination="generic/platform=iOS"
        elif [[ "$sdk" == "iphonesimulator" ]]; then
            # 部分机器可能Simulator列表不同，为了保险，直接通过命令行，取到最新可用的Simulator的UUID
            # 注意一个大坑：instruments这个命令行，会取默认xcode-select指定的版本的模拟器列表，就算你用绝对路径执行它也是，暂时没改这种模式
            # 换一种方案，执行一个空的xcodebuild输出模拟器架构列表：https://stackoverflow.com/questions/32355513/creating-watchos2-simulator-build-using-xcodebuild
            echo "CLOUD_BUILD_INFO_LOG: 检测到模拟器架构，开始获取可用的Simulator UUID"
            if [ ! -z "$workspace_name" ];then
                SIMULATOR_TARGET_DESTINATION=$(${xcodebuild_path} -workspace ${workspace_name} -scheme ${scheme} -configuration ${configuration} -destination 'platform=iOS Simulator' 2>&1 >/dev/null | grep id: | head -n 1 | awk '{print $4}' | tr ":" "=" | tr -d ",")
            else
                SIMULATOR_TARGET_DESTINATION=$(${xcodebuild_path} -project ${project_name} -scheme ${scheme} -configuration ${configuration} -destination 'platform=iOS Simulator' 2>&1 >/dev/null | grep id: | head -n 1 | awk '{print $4}' | tr ":" "=" | tr -d ",")
            fi
            echo "CLOUD_BUILD_INFO_LOG: 获取到第一个可用的Simulator UUID为：$SIMULATOR_TARGET_DESTINATION"
            xcodebuild_destination="platform=iOS Simulator,$SIMULATOR_TARGET_DESTINATION"
        else
            echo "error:unsupport sdk var"
            return 1
        fi
    fi

    xcodebuild_command="${xcodebuild_command} -destination '${xcodebuild_destination}'"

    if [[ ! -n "${new_build_system}" || "${new_build_system}" == "" ]]; then
        xcodebuild_command="${xcodebuild_command}"
    else
        xcodebuild_command="${xcodebuild_command} -UseModernBuildSystem=${new_build_system}"
    fi

    if [ ! -z "$build_action" ];then
        xcodebuild_command="${xcodebuild_command} ${build_action}"
    else
        echo "error:unknow input build_action"
    fi

    xcodebuild_command="${xcodebuild_command} | tee ${TARGETCODEPATH}/products/xcodebuild.log"

    #building
    cd "$cwd"

    echo "CLOUD_BUILD_INFO_LOG: 当前执行xcodebuild路径是："
    pwd
    echo "CLOUD_BUILD_INFO_LOG: xcodebuild 信息"
    echo ${xcodebuild_command}

    if [[ "$use_xcpretty" == "Yes" ]] || [[ "$use_xcpretty" == "true" ]] || [[ "$USE_XCPRETTY" == "Yes" ]] || [[ "$USE_XCPRETTY" == "true" ]];then
        echo "CLOUD_BUILD_INFO_LOG: 使用xcpretty"
        build_error_log_path="${TARGETCODEPATH}/products/builderror.log"
        xcpretty_command="bundle exec xcpretty --error-log-path=${build_error_log_path}"
    fi
    
    if [[ "$use_xcpretty" == "Yes" ]] || [[ "$use_xcpretty" == "true" ]] || [[ "$USE_XCPRETTY" == "Yes" ]] || [[ "$USE_XCPRETTY" == "true" ]];then
        set -o pipefail && eval "${xcodebuild_path}" "${xcodebuild_command}" 2>&1 | eval "${xcpretty_command}"
    else
        set -o pipefail && eval "${xcodebuild_path}" "${xcodebuild_command}" 2>&1
    fi

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "CLOUD_BUILD_ERROR_LOG: xcodebuild编译失败"
        echo `echo "CLOUD_BUILD_ERROR_LOG:" & cat ${build_error_log_path}`
        if [[ "$use_xcpretty" == "Yes" ]] || [[ "$use_xcpretty" == "true" ]] || [[ "$USE_XCPRETTY" == "Yes" ]] || [[ "$USE_XCPRETTY" == "true" ]]; then
            echo "CLOUD_BUILD_ERROR_LOG: 输出builderror.log存放路径：${build_error_log_path}"
            cat ${build_error_log_path} | true
        fi
    fi

    echo "CLOUD_BUILD_INFO_LOG: 执行Xcode编译模板成功结束"
    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
}

# step 7 export
function xcodebuild_export() {

    cd "$cwd"

    if [ -z "$sdk" ];then
        export sdk="$SDK"
    fi

    if [ -z "$sdk" ];then
        export sdk="iphoneos"
    fi

    if [ -z "$xcodebuild_path" ];then
        export xcodebuild_path="$XCODEBUILD_PATH"
    fi

    if [ -z "$xcodebuild_path" ];then
        export xcodebuild_path="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
    fi

    if [ -z "$scheme" ];then
        export scheme="$SCHEME"
    fi

    if [ -z "$product_name" ];then
        export product_name="$PRODUCT_NAME"
    fi

    if [ -z "$product_name" ];then
        export product_name="$SCHEME"
    fi

    bit env set "product_name" "$product_name"

    if [ -z "$xcarchive_path" ];then
        export xcarchive_path="$XCARCHIVE_PATH"
    fi

    # args
    echo export_option_plist_path:"$export_option_plist_path"
    echo TARGETCODEPATH:"$TARGETCODEPATH"
    echo sdk:"$sdk"
    echo xcodebuild_path:"$xcodebuild_path"
    echo scheme:"$scheme"
    echo product_name:"$product_name"
    echo xcarchive_path:"$xcarchive_path"


    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
    echo "CLOUD_BUILD_INFO_LOG: 执行Xcode导出ipa模板"
    # Podfile 文件所在目录
    # 模拟器不支持exportIpa，直接构造一个近似的ipa结构
    # Payload/${scheme}.app
    if [[ ${sdk} == "iphonesimulator" ]]; then
        app_path="${xcarchive_path}/Products/Applications/${product_name}.app"
        if [[ -f "${WORKSPACE_PATH}/../bit_xcodebuild_env" ]];then
            exec_folder_path=`cat "\${WORKSPACE_PATH}/../bit_xcodebuild_env" | awk -F= '{if($1=="EXECUTABLE_FOLDER_PATH"){print $2}}'`
            real_app_path=`cat "\${WORKSPACE_PATH}/../bit_xcodebuild_env" | awk -F= '{if($1=="CODESIGNING_FOLDER_PATH"){print $2}}'`
            # 模拟器没有xcarchive_path模拟一个
            mkdir -p "${xcarchive_path}/Products/Applications"
            cp -r "$real_app_path" "${xcarchive_path}/Products/Applications"
            app_path="${xcarchive_path}/Products/Applications/$exec_folder_path"
            # 模拟dSYMs
            dsym_folder="${xcarchive_path}/dSYMs"
            mkdir -p "$dsym_folder"
            real_dsym_folder=`cat "\${WORKSPACE_PATH}/../bit_xcodebuild_env" | awk -F= '{if($1=="DWARF_DSYM_FOLDER_PATH"){print $2}}'`
            find ${real_dsym_folder} -iname "*.dSYM" -type d -exec cp -r {} "$dsym_folder" \;
        fi
        if [[ ! -d ${app_path} ]]; then
            echo "CLOUD_BUILD_ERROR_LOG: 指定模拟器架构，但是获取xcarchive中的app包失败。在bit-xcodebuild中开启export_envs会插入build_phase导出env，可以准确计算出app路径。"
            return 1
        fi
        echo "CLOUD_BUILD_INFO_LOG: 指定模拟器架构，开始封装导出ipa"
        cd ${TARGETCODEPATH}/products
        mkdir Payload
        cp -r ${app_path} Payload
        # 压缩后改名
        zip -r ${scheme}.ipa Payload
        # 删除临时文件，避免后续被误上传到tos上
        rm -rf Payload
        echo "CLOUD_BUILD_INFO_LOG: ------------------------"
        return 0
    fi

    ## 2.打印Xcode版本
    echo "CLOUD_BUILD_INFO_LOG: Xcode版本: "
    ${xcodebuild_path} -version

    ## 3.导出ipa export
    echo "CLOUD_BUILD_INFO_LOG: plist文件路径："
    echo "$export_option_plist_path"
    xcodebuild_export_command="-exportArchive -archivePath ${xcarchive_path} -exportPath ${TARGETCODEPATH}/products -exportOptionsPlist ${export_option_plist_path} ${xcodebuild_export_extra}"

    echo "CLOUD_BUILD_INFO_LOG: xcodebuild export 信息"
    echo ${xcodebuild_export_command}

    ${xcodebuild_path} ${xcodebuild_export_command} 2>&1

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "CLOUD_BUILD_ERROR_LOG: ipa export导出失败"
        return 1
    fi

    if [[ "${build_size_ipa}" == "Yes" ]] || [[ "${build_size_ipa}" == "true" ]]; then
        echo "CLOUD_BUILD_INFO_LOG: 开始执行包大小的专用包导出操作"
        sizeipa_export_pn=$(echo ${export_option_plist_path}| awk -F "." '{print $1}')
        sizeipa_plist_path=${sizeipa_export_pn}Thin.plist

        xcodebuild_export_command="-exportArchive -archivePath ${xcarchive_path} -exportPath ${TARGETCODEPATH}/products/Sizeipa -exportOptionsPlist ${sizeipa_plist_path} ${xcodebuild_export_extra}"

        echo "CLOUD_BUILD_INFO_LOG: xcodebuild export size_ipa 信息"
        echo ${xcodebuild_export_command}

        ${xcodebuild_path} ${xcodebuild_export_command} 2>&1

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "CLOUD_BUILD_ERROR_LOG: size ipa export导出失败"
            exit 1
        fi
        mv ${TARGETCODEPATH}/products/Sizeipa/Apps/*ipa ${TARGETCODEPATH}/products/Sizeipa
        #mv ${TARGETCODEPATH}/products/Sizeipa/app-thinning.plist ${TARGETCODEPATH}/products/Sizeipa
    fi
    echo "CLOUD_BUILD_INFO_LOG: ------------------------"

}

# step 8 收集构建产物，例如dsym
function collect_data() {
    if [ -z "$POD_PATH" ];then
    podfile_path=`find $TARGETCODEPATH -iname Podfile | head -1`
    POD_PATH=`dirname "$podfile_path"`
    fi

    if [ -z "$POD_PATH" ];then
        >&2 echo "undefined POD_PATH"
        >&2 echo "未找到 POD_PATH"
    fi

    if [[ "$product_name" == "" ]]; then
        export product_name="$SCHEME"
    fi

    if [[ "$enable_upload_xclog" == "" ]]; then
        export enable_upload_xclog="Yes"
    fi

    if [[ "$enable_package_dsym_to_products" == "" ]]; then
        export enable_package_dsym_to_products="Yes"
    fi

    if [[ "$enable_package_linkmap_to_products" == "" ]]; then
        export enable_package_linkmap_to_products="NO"
    fi

    if [[ "$enable_copy_podfile_to_products" == "" ]]; then
        export enable_copy_podfile_to_products="Yes"
    fi

    if [[ "$enable_copy_podfile_lock_to_products" == "" ]]; then
        export enable_copy_podfile_lock_to_products="Yes"
    fi

    if [[ "$enable_copy_podfile_patch_to_products" == "" ]]; then
        export enable_copy_podfile_lock_to_products="Yes"
    fi

    if [[ "$enable_copy_version_json_to_products" == "" ]]; then
        export enable_copy_version_json_to_products="Yes"
    fi

    echo "CLOUD_BUILD_INFO_LOG: -----------------------"
    echo "CLOUD_BUILD_INFO_LOG: 收集构建产物"
    # upload dsym
    if [[ "$enable_package_dsym_to_products" == "Yes" ]] || [[ "$enable_package_dsym_to_products" == "true" ]]; then
        if [ -d "${XCARCHIVE_PATH}/dSYMs" ];then
            cd "${XCARCHIVE_PATH}/dSYMs"
            if [ ! -d "${product_name}.app.dSYM" ];then
                echo "${product_name}.app.dSYM 文件不存在。可能需要设置product_name，以便获取正确的文件位置。"
            fi
            zip -r "${SCHEME}.dSYM.zip" "${product_name}.app.dSYM"
            mv "${XCARCHIVE_PATH}/dSYMs/${SCHEME}.dSYM.zip" "${TARGETCODEPATH}/products/"
        else
            echo "CLOUD_BUILD_INFO_LOG: 不处理dsym文件"
        fi
    fi

    # upload dsyms
    if [[ "$enable_package_dsyms_to_products" == "Yes" ]] || [[ "$enable_package_dsyms_to_products" == "true" ]]; then
        if [ -d "${XCARCHIVE_PATH}/dSYMs" ];then
            cd ${XCARCHIVE_PATH}
            rm -rf "${XCARCHIVE_PATH}/${SCHEME}.dSYM.zip"
            mv "./dSYMs" "${SCHEME}.dSYM"
            zip -r "${XCARCHIVE_PATH}/${SCHEME}.dSYM.zip" "${SCHEME}.dSYM"
            mv "${SCHEME}.dSYM" "./dSYMs"
            mv "${XCARCHIVE_PATH}/${SCHEME}.dSYM.zip" "${TARGETCODEPATH}/products/"
            cd -
        else
            echo "CLOUD_BUILD_INFO_LOG: 不处理dsym文件"
        fi
    fi

    # link map
    if [[ "$enable_package_linkmap_to_products" == "Yes" ]] || [[ "$enable_package_linkmap_to_products" == "true" ]]; then
        if [[ ${BUILD_ACTION} != "archive" ]]; then
            linkMapPath="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-${SDK}"
        else
            linkMapPath="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/BuildProductsPath/${CONFIGURATION}-${SDK}"
        fi
        echo "CLOUD_BUILD_INFO_LOG: 打印LinkMap主目录"
        echo ${linkMapPath}
        ProjName=$(basename $WORKSPACE_PATH| awk -F "." '{print $1}')
        linkMapPathSec="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/IntermediateBuildFilesPath/${ProjName}.build/${CONFIGURATION}-${SDK}/${SCHEME}.build"
        if [ -d ${linkMapPath} ]; then
            cd ${linkMapPath}
            linkMapName=$(find . -name "${product_name}-LinkMap-*arm64.txt")
            if [[ -f ${linkMapName} && -n ${linkMapName} ]]; then
                echo "CLOUD_BUILD_INFO_LOG: 在LinkMap主目录找到linkmap文件"
                mv ${linkMapName} "${TARGETCODEPATH}/products/"
                # 适配linkMap.zip的需求
                cd "${TARGETCODEPATH}/products"
                rm -rf LinkMap
                rm -rf LinkMap.zip
                zip -r LinkMap.zip ${linkMapName}
            fi
        fi
        echo "CLOUD_BUILD_INFO_LOG: 打印LinkMap备目录"
        echo ${linkMapPathSec}
        if [ -d ${linkMapPathSec} ]; then
            cd ${linkMapPathSec}
            linkMapName=$(find . -name "${product_name}-LinkMap-*arm64.txt")
            if [[ -f ${linkMapName} && -n ${linkMapName} ]]; then
                echo "CLOUD_BUILD_INFO_LOG: 在LinkMap备目录找到linkmap文件"
                mv ${linkMapName} "${TARGETCODEPATH}/products/"
                # 适配linkMap.zip的需求
                cd "${TARGETCODEPATH}/products"
                rm -rf LinkMap
                rm -rf LinkMap.zip
                zip -r LinkMap.zip ${linkMapName}
            fi
        fi
    fi

    if [[ "$enable_copy_podfile_to_products" == "Yes" ]] || [[ "$enable_copy_podfile_to_products" == "true" ]]; then
        cp ${POD_PATH}/Podfile "${TARGETCODEPATH}/products"
    fi

    if [[ "$enable_copy_podfile_lock_to_products" == "Yes" ]] || [[ "$enable_copy_podfile_lock_to_products" == "true" ]]; then
        if [[ -e ${POD_PATH}/Podfile.lock ]]; then
            cp ${POD_PATH}/Podfile.lock "${TARGETCODEPATH}/products/"
        fi
    fi

    if [[ "$enable_copy_podfile_patch_to_products" == "Yes" ]] || [[ "$enable_copy_podfile_patch_to_products" == "true" ]]; then
        if [[ -e ${POD_PATH}/Podfile_Patch ]]; then
            cp ${POD_PATH}/Podfile_Patch "${TARGETCODEPATH}/products/"
        fi
    fi

    if [[ "$enable_copy_version_json_to_products" == "Yes" ]] || [[ "$enable_copy_version_json_to_products" == "true" ]]; then
        ## 把version.json放到产物中，现在这个文件用于很多下游任务，包括覆盖率，Sladar上传的源码文件映射表等
        if [[ -e ${TARGETCODEPATH}/version.json ]]; then
            cp ${TARGETCODEPATH}/version.json "${TARGETCODEPATH}/products/"
        fi
    fi

}

# step 9 分析构建日志
function analyze_build_log() {
    curl https://ios.bytedance.net/wlapi/tosDownload/iosbinary/indexstore/build_infer_log_tools_for_ci.py -o build_infer_log_tools_for_ci.py --retry 3
    # upload xcactivity log and xcresultbundle
    export BD_DERIVED_PATH="$DERIVED_DATA_PATH"
    xcrun python3 build_infer_log_tools_for_ci.py --upload-deriveddata-logs --value 1 2>&1
}




# function check_tool() {
#     # if ! command -v toscli; then
#     if [[ $(uname -s) == "Darwin" ]]; then
#         wget http://voffline.byted.org/download/tos/schedule/cloudbuild/bin/toscli-darwin -O toscli
#     else
#         wget http://voffline.byted.org/download/tos/schedule/cloudbuild/bin/toscli-linux -O toscli
#     fi
#     chmod +x toscli
#     mkdir -p $toscli_file_dir
#     mv toscli "$toscli_file_dir/"
#     echo "Install toscli... SUCCESS"
#     # fi
# }

# function _upload_file_tos() {
#     export upload_result=""
#     local local_file_path="$1"
#     local file_name="$2"
#     if [[ ! -f ${local_file_path} ]]; then
#         echo "{\"code\":400,\"message\":\"empty file\"}"
#         return
#     fi
#     local resp
#     for ((i = 0; i < 3; i++)); do
#         resp=$(toscli put -name "${file_name}" "${local_file_path}")
#         if [[ ${resp} == *"Upload success!"* ]]; then
#             echo "{\"code\":0,\"data\":{\"url\":\"http://voffline.byted.org/download/tos/schedule/${TOS_BUCKET}/${file_name}\"},\"message\":\"success\"}"
#             export upload_result="success"
#             return
#         fi
#         sleep 10 # Wait for 10 seconds before retry.
#     done
#     echo "{\"code\":500,\"message\":\"${resp}\"}"
# }

function save_artifacts() {
    artifacts_map=$1
    if [[ $artifacts_map == "null" || $artifacts_map == "" ]]; then
        echo "no artifacts"
        return 0
    fi
    echo "artifacts_map=$artifacts_map"
    artifacts_len=$(echo $artifacts_map | jq '.|length')
    echo $artifacts_len
    pwd
    for index in $(seq 0 $artifacts_len); do
        if [[ $index == $artifacts_len ]]; then
            continue
        fi
        artifacts_name="name"
        artifacts_type=$(echo $artifacts_map | jq -r ".[$index].type")
        artifacts_path=$(echo $artifacts_map | jq -r ".[$index].path")
        if [[ $artifacts_path == "" ]]; then
            echo "artifacts_type:$artifacts_type, artifacts_path is empty:$artifacts_path"
            return 0
        fi
        file_size=""
        file_md5=""
        #tos_path="${TOS_PREFIX}/${TASK_ID}/${artifacts_name}"
        echo "artifacts_type:$artifacts_type"
        echo "artifacts_path:$artifacts_path"
        cd ${TARGETCODEPATH}
        pwd
        is_exist=$(find ${artifacts_path} -name "*")
        echo $is_exist
        resp=""
        full_dir=${TARGETCODEPATH}
        if [[ ! -z $is_exist ]]; then
            echo "files $is_exist"
            for file_path in ${is_exist[@]}; do
                echo $file_path
                file_name=${file_path##*/}
                echo $file_name
                echo "file path ${file_path} exist"
                
                if [[ "$APP_CLOUD_ID" != "" ]]; then
                    if [[ "${file_name}" =~ ".dSYM" ]]; then
                        upload_slardar_ios "${file_path}" "slardar_ios_upload" &
                    fi
                fi

                tos_path="$TOS_PREFIX/${TASK_ID}/$file_name"
                if [[ -f ${file_path} ]]; then
                    echo "upload file:${file_path}"
                    #node -v
                    #node $WORKSPACE/cloud_build/common/upload/upload.js "${file_path}" "${TASK_ID}/$file_name"
                    _upload_file_tos "${file_path}" "${TASK_ID}/$file_name"
                    echo "upload end _upload_file_tos"
                    if [[ ${upload_result} != "success" ]]; then
                        echo "upload artifacts $file_name to tos fail"
                        #bash $update_task_step -j "fail" -g "upload artifacts" -s 0 -m "end $file_name" -n "$file_name" -t "end"
                    else
                        echo "begin to get output info"
                        #tos_path=$(echo "$resp" | jq ".data.url")
                        if [[ $tos_path == "" ]]; then
                            echo "upload artifact $file_name fail"
                        fi
                        echo "begin to get md5sum info:${file_path}"
                        md5_cmd=$(which md5sum)
                        if [[ ! -z $md5_cmd ]]; then
                            file_md5=$(md5sum ${file_path} | awk '{print $1}')
                        elif [[ ! -z $(which md5) ]]; then
                            file_md5=$(md5 ${file_path} | awk '{print $4}')
                        fi
                        echo "begin to get file_size info:${file_path}"
                        file_size=$(ls -la $file_path | awk '{print $5}')
                        if [[ ${artifacts_output} == "[" ]]; then
                            artifacts_output="$artifacts_output{\"name\":\"$file_name\",\"url\":\"$tos_path\",\"type\":\"$artifacts_type\",\"md5\":\"$file_md5\",\"size\":$file_size}"
                        else
                            artifacts_output="$artifacts_output,{\"name\":\"$file_name\",\"url\":\"$tos_path\",\"type\":\"$artifacts_type\",\"md5\":\"$file_md5\",\"size\":$file_size}"
                        fi
                        echo "get file artifacts info end:${file_path}"

                        #bash $update_task_step -j "success" -g "upload artifacts" -s 0 -m "end $file_name" -n "$file_name" -t "end"
                    fi
                else
                    echo "file ${file_path} not exist"
                fi
            done
        else
            echo "path ${artifacts_path} not exist"
        fi
        echo "save artifacts end"
    done

}

# step 10 上传产物 上传方式和保存路径还没确定
function upload_slardar_ios() {
    file_path_dysm=$1
    router=$2
    SlardarDomain="http://symbolicate.byted.org"
    if [[ "${overSeaApp}" == "true" ]]; then
        SlardarDomain="http://symbolicateus.byted.org"
    fi
    echo "begin to upload dysm: ${SlardarDomain}"
    for ((i = 0; i < 5; i++)); do
        ret=$(curl -v -X POST \
            ${SlardarDomain}/${router} \
            -H 'content-type: multipart/form-data' \
            -F file=@$file_path_dysm -F aid=${APP_CLOUD_ID})

        echo ${ret}
        errmsg=$(echo $ret | jq -r ".err")

        if [ "$errmsg" != 'ok' ]; then
            echo -e "上传 Slardar 失败"
            echo ${errmsg}
        else
            echo -e "上传 Slardar 成功"
            return
        fi
    done
    if [[ $ApiType == "template_bit" ]]; then
        echo "上传 Slardar 失败 end"
        #exit 1
    fi
}

function upload_artifacts() {
    export TOS_PREFIX="https://voffline.byted.org/download/tos/schedule/iOSPackageBackUp"
    export artifacts_output="[]"
    export TOS_BUCKET="iOSPackageBackUp"
    export TOS_ACCESS_KEY="V1IIUCA4LME9VU4NGQY3"
    export TOS_ENDPOINT="tos-cn-north.byted.org"

    toscli_file_dir="$WORKSPACE/toscli_dir"
    export PATH="$toscli_file_dir:$PATH"

    check_tool
    echo "begin to upload artifact origin:$artifacts_path"
    save_artifacts "$artifacts_path"
    export artifacts_output="${artifacts_output}]"
    echo "artifacts_output:${artifacts_output}"
}

#还需要配置全局变量 CLOUD_BUILD_ID_RSA_KEY GIT_ACCOUNT_NAME GIT_ACCOUNT_EMAIL
export WORKSPACE="/Users/bytedance/Desktop/testbuild"
TARGETCODEPATH="/Users/bytedance/Desktop/testbuild/TobBundle"
#step 1 需要参数 MAIN_GIT_URL和MAIN_GIT_BRANCH
MAIN_GIT_URL="git@code.byted.org:mPaaS/TobBundle.git"
clone_main_code
#setp 2
bundler_env
#setp 3 需要参数 cert_url，暂时用本地路径来测试
cert_url="${TARGETCODEPATH}/Project/Provisions/NetWorkInHousePriv.p12"
cert_passwd="bytedance"
login_passwd="******"
cert_install
#step 4 需要参数 PROV_PATH
PROV_PATH="${TARGETCODEPATH}/Project/Provisions"
provision_install
#step 5 
pod_update
#step 6 需要参数 cwd workspace_name scheme configuration
cwd="${TARGETCODEPATH}/Project"
scheme="TobBundle_InHouse"
configuration="Release"
xcodebuild
#step 7 需要参数 export_option_plist_path
export_option_plist_path="${TARGETCODEPATH}/Project/ExportPlists/TobBundle_InHouse.plist"
xcodebuild_export
#step 8 
collect_data
#step 9
analyze_build_log