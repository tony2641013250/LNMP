#!/bin/bash
#
## Installing Subversion
## https://github.com/maicong/LNMP
## Usage: bash svn.sh

clear;

## 检查 root 权限
[ $(id -g) != "0" ] && die "Script must be run as root.";

echo "================================================================";
echo "Installing Subversion";
echo "https://github.com/maicong/LNMP";
echo "Usage: bash svn.sh";
echo "================================================================";

if [ "$*" != '' ]; then
    selected=$1;
else
    echo "[Notice] Please select: "
    select selected in 'Install' 'Uninstall' 'Exit'; do
        break;
    done;
fi;

project='';
projectPath='';
webPath='';
username='';
password=`cat /dev/urandom | head -1 | md5sum | head -c 12`;
ipAddress=`ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\." | head -n 1`;

## 输入 IP 地址
function InputIP()
{
    if [ "$ipAddress" == '' ]; then
        echo '[Error] empty server ip.';
        read -p '[Notice] Please input server ip:' ipAddress;
        [ "$ipAddress" == '' ] && InputIP;
    else
        echo '[OK] Your server ip is:' && echo $ipAddress;
        read -p '[Notice] This is your server ip? : (y/n)' confirmDM;
        if [ "$confirmDM" == 'n' ]; then
            ipAddress='';
            InputIP;
        elif [ "$confirmDM" != 'y' ]; then
            InputIP;
        fi;
    fi;
}

## 输入 项目名称
function InputName()
{
    if [ "$project" == '' ]; then
        read -p '[Notice] Please input project name:' project;
        [ "$project" == '' ] && InputName;
    else
        echo '[OK] Your project name is:' && echo $project;
        read -p '[Notice] This is your project name? : (y/n)' confirmDM;
        if [ "$confirmDM" == 'n' ]; then
            project='';
            InputName;
        elif [ "$confirmDM" != 'y' ]; then
            InputName;
        fi;
    fi;
    projectPath="/var/svn/repos/${project}";
    webPath="/home/wwwroot/${project}";
    username="user-${project}";
    [ -d "${projectPath}" ] && echo "[Error] ${project} is exist!" && project='' && InputName;
    mkdir -p ${projectPath};
}

## 输入 WEB 目录
function InputWebPath()
{
    if [ "$webPath" == '' ]; then
        read -p '[Notice] Please input web directory:' webPath;
        [ "$webPath" == '' ] && InputWebPath;
    else
        echo '[OK] Your web directory is:' && echo $webPath;
        read -p '[Notice] This is your web directory? : (y/n)' confirmDM;
        if [ "$confirmDM" == 'n' ]; then
            webPath='';
            InputWebPath;
        elif [ "$confirmDM" != 'y' ]; then
            InputWebPath;
        fi;
    fi;
    [ -d "${webPath}/.svn/" ] && echo "[Error] ${webPath} is exist!" && webPath='' && InputWebPath;
}

## 安装 SVN
function InstallSVN()
{
    SVN_VSESION=$(rpm -qa --queryformat "%{VERSION}" subversion);
    if [ $(expr "$SVN_VSESION" \< "1.9") == "1" ]; then
        echo -e "[WandiscoSVN]\nname=Wandisco SVN Repo\nbaseurl=http://opensource.wandisco.com/centos/\$releasever/svn-1.9/RPMS/\$basearch/\nenabled=0\ngpgcheck=0\n" > /etc/yum.repos.d/wandisco-svn.repo;
        yum autoremove subversion subversion-libs -y;
        yum install subversion -y --enablerepo WandiscoSVN;
    else
        [ $(rpm -qa subversion | wc -l) == "0" ] && yum install subversion -y;
    fi;

    svnadmin create ${projectPath};

cat >> ${projectPath}/conf/authz << EOF
[/]
${username} = rw
* =
EOF

cat >> ${projectPath}/conf/passwd << EOF
${username} = ${password}
EOF

    svnserve="${projectPath}/conf/svnserve.conf";
    sed -i "s@# anon-access@anon-access@" $svnserve;
    sed -i "s@# auth-access@auth-access@" $svnserve;
    sed -i "s@# password-db = passwd@password-db = ${projectPath}/conf/passwd@" $svnserve;
    sed -i "s@# authz-db = authz@authz-db = ${projectPath}/conf/authz@" $svnserve;

    cp ${projectPath}/hooks/post-commit.tmpl ${projectPath}/hooks/post-commit;
cat > ${projectPath}/hooks/post-commit << EOF
#!/bin/sh

export LANG=en_US.UTF-8

REPOS="\$1"
REV="\$2"
WEB_PATH=${webPath}
LOG_PATH=/tmp/svn_commit.log
SVN_PATH=/usr/bin/svn
SVN_REPOS=svn://localhost/repos/${project}

echo "nnn########## Commit " \`date "+%Y-%m-%d %H:%M:%S"\` '##################' >> \$LOG_PATH
echo \`whoami\`,\$REPOS,\$REV >> \$LOG_PATH
echo \`\$SVN_PATH checkout \$SVN_REPOS \$WEB_PATH --username "$username" --password "$password" --no-auth-cache >> \$LOG_PATH\`
chown -R www:www \$WEB_PATH
EOF

    chmod 755 ${projectPath}/hooks/post-commit;

    firewall-cmd --permanent --zone=public --add-port=3690/tcp;
    firewall-cmd --reload;

    if [ ! -f "/usr/lib/systemd/system/svnserve.service" ]; then
        DIR="$(cd "$(dirname "$0")" && pwd)";
        cp ${DIR}/svnserve/svnserve /etc/sysconfig/;
        cp ${DIR}/svnserve/svnserve.service /usr/lib/systemd/system/;
    fi;

    systemctl enable svnserve.service;
}

## 安装完成
function InstallCompleted()
{
    status='';
    systemctl restart svnserve.service && status='ok';
    if [ "$status" == 'ok' ]; then
        echo "================================================================";
        echo -e "\033[42m [SVN] Install completed. \033[0m";
        echo -e "\033[34m SVN URL: \033[0m svn://${ipAddress}/repos/${project}";
        echo -e "\033[34m Username: \033[0m ${username}";
        echo -e "\033[34m Password: \033[0m ${password}";
        echo "================================================================";
    else
        echo -e "\033[41m [SVN] Sorry, Install Failed. \033[0m";
        echo "Please contact us: https://github.com/maicong/LNMP/issues";
    fi;
}

## 卸载
function Uninstall() {
    yum autoremove subversion subversion-libs -y;
    pgrep svnserve | xargs -r kill;
    rm -rf /etc/sysconfig/svnserve;
    rm -rf /usr/lib/systemd/system/svnserve.service;
    rm -rf /etc/systemd/system/multi-user.target.wants/svnserve.service;
    rm -rf /etc/yum.repos.d/wandisco-svn.repo;
    echo -e "\033[42m [NOTICE] \033[0m Uninstall successful! The repository directory is \033[34m/var/svn/repos/\033[0m , You can delete it.";
}

if [ "$selected" == 'Install' ]; then
    InputIP;
    InputName;
    InputWebPath;
    InstallSVN;
    InstallCompleted;
elif [ "$selected" == 'Uninstall' ]; then
    read -p '[Notice] Are you sure? (y/n) : ' confirmYN;
    [ "$confirmYN" != 'y' ] && exit;
    Uninstall;
else
    exit;
fi;