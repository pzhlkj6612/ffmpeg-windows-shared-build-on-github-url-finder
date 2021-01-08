#!/usr/bin/env bash


# https://docs.github.com/en/free-pro-team@latest/rest/overview/resources-in-the-rest-api
#
# https://stedolan.github.io/jq/manual/
# https://stackoverflow.com/questions/42746828/jq-how-to-filter-a-json-that-does-not-contain
# https://gist.github.com/olih/f7437fb6962fb3ee9fe95bda8d2c8fa4#gistcomment-3345841
#
# https://stackoverflow.com/questions/40027395/passing-bash-variable-to-jq
#
# https://www.cyberciti.biz/faq/bash-while-loop/
# https://linuxize.com/post/bash-increment-decrement-variable/
#
# https://unix.stackexchange.com/questions/354943/setting-jq-output-to-a-bash-variable

# Oh it's difficult.


COMMON_HEADER='Accept: application/vnd.github.v3+json'
COMMON_PARAMETER='per_page=100'
FFMPEG_URL_BtbN='https://api.github.com/repos/BtbN/FFmpeg-Builds/releases'
FFMPEG_URL_gyan_dev='https://api.github.com/repos/GyanD/codexffmpeg/releases'
MAXIMUM_PAGE=20


ffmpeg_provider=$1 # 'BtbN' or 'gyan.dev'
ffmpeg_ver=$2 # '4.3.1'


jqFilenameConditions=' ( .name | endswith(".zip") ) ' # I only need the zip packages.


if [ "${ffmpeg_provider}"  = 'BtbN' ]; then
    ffmpegUrl=${FFMPEG_URL_BtbN}

    jqFilenameConditions=" ${jqFilenameConditions} and
        ( .name | contains(\"-gpl-shared\") ) and
        ( .name | contains(\"vulkan\") | not )
    "
elif [ "${ffmpeg_provider}" = 'gyan.dev' ]; then
    ffmpegUrl=${FFMPEG_URL_gyan_dev}

    jqFilenameConditions=" ${jqFilenameConditions} and
        ( .name | contains(\"full_build-shared\") )
    "
else
    echo "::error ::No such provider '${ffmpeg_provider}', you can use 'BtbN' or 'gyan.dev'."
    exit 1
fi

if [ -z "${ffmpeg_ver}" ]; then
    # To find the latest release

    if [ "${ffmpeg_provider}" = 'gyan.dev' ]; then
        echo "::error ::Provider 'gyan.dev' does not support 'latest' version. You neet to specify the version number."
        exit 2
    fi

    ffmpegUrl="${ffmpegUrl}/latest"

    jqFilenameConditions=" ${jqFilenameConditions} and
        ( .name | contains(\"-N-\") )
    "
else
    ffmpegUrl="${ffmpegUrl}?${COMMON_PARAMETER}"

    jqFilenameConditions=" ${jqFilenameConditions} and
        ( .name | contains(\"${ffmpeg_ver}-\") )
    "
fi

echo "ffmpegUrl = ${ffmpegUrl}"
echo -e "jqFilenameConditions = \n${jqFilenameConditions}"

gotFFmpegAssetUrl=0

if [ -z "${ffmpeg_ver}" ]; then
    result=$( curl \
        -H "${COMMON_HEADER}" \
        "${ffmpegUrl}" | \
        jq --raw-output "
            .assets[] |
            select ( ${jqFilenameConditions} ) |
            .browser_download_url
    " )
    exitCode=${?}
    [ ${exitCode} -ne 0 ] && echo "::error ::jq exited with ${exitCode}." && break

    if [ -n "${result}" ]; then
        echo "browser_download_url = ${result}"
        echo "::set-output name=browser_download_url::${result}"

        gotFFmpegAssetUrl=1
    fi
else
    pageNum=0 # Well, starting from 1

    while [ ${gotFFmpegAssetUrl} -ne 1 ]; do
        let "pageNum++"
        echo "ffmpegUrl = ${ffmpegUrl}&page=${pageNum}"

        resultCurl=$( curl \
            -H "${COMMON_HEADER}" \
            "${ffmpegUrl}&page=${pageNum}" 
        )
        resultJq=$( echo ${resultCurl} | \
            jq --raw-output "
                [
                    .[].assets[] |
                    select ( ${jqFilenameConditions} ) |
                    .browser_download_url
                ] |
                .[0]
            " ) # Need the first one.
        exitCode=${?}
        [ ${exitCode} -ne 0 ] &&
        echo "::error ::jq exited with ${exitCode}." &&
        echo -e "resultCurl = \n${resultCurl}" &&
        break

        if [ -n "${resultJq}" ]; then
            echo "browser_download_url = ${resultJq}"
            echo "::set-output name=browser_download_url::${resultJq}"

            gotFFmpegAssetUrl=1
        fi

        [ ${pageNum} -eq ${MAXIMUM_PAGE} ] && break
    done
fi

if [ ${gotFFmpegAssetUrl} -eq 0 ]; then
    echo "::error ::Cannot get ffmpeg asset url."
    exit 3
fi
