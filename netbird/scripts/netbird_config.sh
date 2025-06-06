#!/bin/sh 
source /koolshare/scripts/base.sh
eval $(dbus export netbird) 
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
LOGFILE=/tmp/upload/netbird_log.txt 
LOGUPDATEFILE=/tmp/upload/netbird_update_log.txt 


case $1 in
start)
	if [ "${netbird_enable}" == "1" ];then
		echo start by wan-start >> ${LOGFILE}
	else
		logger "netbird插件未开启，跳过！"
	fi
	;;
esac

# submit by web
case $2 in
web_submit)
    echo "" > ${LOGFILE}
	echo_date "netbird merlin addon by zhaxg" >> ${LOGFILE}
    echo_date "netbird_enable:${netbird_enable}" >> ${LOGFILE}
    echo_date "netbird_setup_key:${netbird_setup_key}" >> ${LOGFILE}
	http_response "$1"
    if [ "${netbird_enable}" == "1" ];then
        echo_date "准备启动netbird" >> ${LOGFILE}
		/koolshare/scripts/netbird_service.sh start       
        echo_date "netbird started please wait ..." >> ${LOGFILE}
	else
        echo_date "准备关闭netbird" >> ${LOGFILE}
        netbird down
		/koolshare/scripts/netbird_service.sh stop
        sleep 3
	fi

    echo_date "操作完成" >> ${LOGFILE}
    echo "XU6J03M6" >> ${LOGFILE}
	;;
update)
    echo "" > ${LOGUPDATEFILE}
    http_response "update netbird please wait ..."
    
    latest_version_url="https://api.github.com/repos/netbirdio/netbird/releases/latest"
    latest_version_file="/tmp/netbird_latest_version.json"
    echo_date "准备更新，检测最新版本：$latest_version_url" >> ${LOGUPDATEFILE}
 
    wget "$latest_version_url" -O "$latest_version_file"
    tag_name=$(cat $latest_version_file | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    download_url=$(cat $latest_version_file | grep '"browser_download_url":' | grep 'linux_arm64.tar.gz' | sed -E 's/.*"([^"]+)".*/\1/')
 
    if [[ "$tag_name" == "$netbird_version" ]]; then
        echo_date "当前版本已是最新($netbird_version)，无需更新。" >> ${LOGUPDATEFILE} 
    else
        echo_date "当前版本：$netbird_version, 最新版本：$tag_name, 开始更新" >> ${LOGUPDATEFILE}
        dbus set netbird_version="$tag_name"

        wget -O /tmp/netbird.tar.gz "https://ghfast.top/${download_url}" 2>&1 | tee ${LOGUPDATEFILE}
        tar -xzf /tmp/netbird.tar.gz -C /koolshare/bin/
        chmod 755 /koolshare/bin/netbird

        echo_date "准备重新启动netbird" >> ${LOGUPDATEFILE}
		/koolshare/scripts/netbird_service.sh restart
        nohup netbird up >> $LOGFILE 2>&1 &
    fi

    echo_date "操作完成" >> ${LOGUPDATEFILE}
    echo "XU6J03M6" >> ${LOGUPDATEFILE} 
    
    ;;
status)
    #状态
    STATUS=$(netbird status)
    ENCODED_STATUS=$(echo "base64://"$(printf "%s" "$STATUS" | base64))
    
    #正常情况直接返回链接状态
    if printf '%s' "$STATUS" | grep "Signal: Connected"; then 
        netbird status --yaml > ${LOGFILE} #状态正常重置日志文件为详细状态信息
        echo "XU6J03M6" >> ${LOGFILE}
        http_response $ENCODED_STATUS
        return 0 
    fi
 
    if printf '%s' "$STATUS" | grep -E "Signal: Disconnected|Daemon status: NeedsLogin"; then
        #echo "XU6J03M6" >> ${LOGFILE}

        #如果检测到登录成功，则提示用户连接
        LOGIN_SUCCESS=$(grep -oE "Logging successfully" "$LOGFILE" | tail -n1)
        if  [[ -n "$LOGIN_SUCCESS" ]]; then
            nohup netbird up >> $LOGFILE 2>&1 &
            sleep 3 #等待启动完成
            http_response "成功完成登录，正在启动连接，请稍等..."
            return 0
        fi

        #如果检测到SSO登录URL，则提示用户登录
        LOGIN_URL=$(grep -oE "https?://[^ ]*activate\?user_code=[^ ]+" "$LOGFILE" | tail -n1) 
        if  [[ -n "$LOGIN_URL" ]]; then
            MESSAGE="需要授权登录：<span class='auth-link'><a href='$LOGIN_URL' target='_blank'>$LOGIN_URL</a></span>"
            ENCODED_MESSAGE=$(echo "base64://"$(printf "%s" "$MESSAGE" | base64))
            http_response $ENCODED_MESSAGE
            return 0
        fi

        #根据不同的场景进行登录认证
        echo "" > ${LOGFILE} 
        if [[ -n "$netbird_setup_key" ]]; then
            echo_date "使用netbird_setup_key登录：${netbird_setup_key}" >> ${LOGFILE}
            nohup netbird login -k ${netbird_setup_key} >> $LOGFILE 2>&1 &
        else
            nohup netbird login >> $LOGFILE 2>&1 &
        fi
        sleep 3 #等待登录完成
        http_response "正在登录中，请稍等..."
        return 0 
    fi 

    ERRMSG="netbird-up无法重新建立连接，重试中，请稍等..."
    http_response $ERRMSG
    ;;
esac