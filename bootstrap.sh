#!/bin/sh
#set -x

green="\e[0;92m"
red="\e[0;91m"
reset="\e[0m"

DATABASE="postfix"

DB_USER="postfix"
DB_PASSWORD=`openssl rand -base64 8 | tr -d =`

#This is only for the cert issue function
EMAIL="postmaster@${DOMAIN}"

DB_ROOT_PASSWORD=`openssl rand -base64 8 | tr -d =`

#This is VMAIL 
UID="7000"
GID="7000"

# The SQL queries
SQL_DB="CREATE DATABASE IF NOT EXISTS ${DATABASE};"

SQL_USER="CREATE USER IF NOT EXISTS ${DB_USER}@localhost \
          IDENTIFIED BY '${DB_PASSWORD}';"

SQL_PERM="GRANT SELECT,INSERT,UPDATE,DELETE ON ${DATABASE}.* \
          TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"

#FIXME Maybe just init the database with a dump and save all the hassle here
# e.g mysql < postfix.sql

SQL_TBL_DOMAIN='CREATE TABLE IF NOT EXISTS `virtual_domains` 
                (`id` int(11) NOT NULL auto_increment, 
                `name` varchar(50) NOT NULL, 
                PRIMARY KEY (`id`) ) ENGINE=InnoDB DEFAULT CHARSET=utf8;' 

SQL_TBL_USERS='CREATE TABLE IF NOT EXISTS `virtual_users` (
               `id` int(11) NOT NULL auto_increment,
               `domain_id` int(11) NOT NULL,
               `email` varchar(100) NOT NULL,
               `password` varchar(150) NOT NULL,
               PRIMARY KEY (`id`),
               UNIQUE KEY `email` (`email`),
               FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
               ) ENGINE=InnoDB DEFAULT CHARSET=utf8;'

SQL_TBL_ALIAS='CREATE TABLE IF NOT EXISTS `virtual_aliases` (
                 `id` int(11) NOT NULL auto_increment,
                 `domain_id` int(11) NOT NULL,
                 `source` varchar(100) NOT NULL,
                 `destination` varchar(100) NOT NULL,
                 PRIMARY KEY (`id`),
                 FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
                 ) ENGINE=InnoDB DEFAULT CHARSET=utf8;'

# The next 3 is what's usually done by mysql_secure_install
SQL_ROOT_PW='UPDATE mysql.user SET Password=PASSWORD(`$DB_ROOT_PASSWORD`) WHERE
          User=`root`;'

SQL_ROOT_REMOTE='DELETE FROM mysql.user WHERE User='root' AND Host NOT IN
                ('localhost', '127.0.0.1', '::1');'

SQL_RM_ANON='DELETE FROM mysql.user WHERE User='';'


# Check the arguements
#XXX this is not all complete

echo $#
if [ $# -eq 0 ]; then
    echo "bootstrap [--verbose] --domain=FQDN"
    exit
else
echo $@
while [ $# -gt 0 ]; do
case "${1}" in
    -v|--verbose)   verbose= 
                    set -x
                    set -v
                    shift 
                    ;;
    --domain=*) DOMAIN=${1#--domain=}
                ${DOMAIN:?"Can't be empty"}
                break
                ;;
    *) echo "Unknown or wrong arguments"
       exit
       ;;
esac
done
fi

_return() {
    if [ "$?" -ne 0 ]; then
        echo "${red}Something went wrong in\t$1${reset}"
        exit 1
    else
        echo "${green}Operation $1\tfinished without noticible error${reset}"
    fi
}

_gen_pw() {
        local GEN_PASSWORD="`openssl rand -base64 8 | tr -d =`"
        echo $GEN_PASSWORD
}

_update() {
        echo "${green}Checking if Host is up-to-date${reset}"
        aptitude ${verbose--q } update
        aptitude ${verbose--q } full-upgrade
        _return "Update"
}

_packages() {
        echo "${green}Installing Packages${reset}"
        aptitude ${verbose--q } install \
            postfix-mysql \
            dovecot-core \
            dovecot-mysql \
            dovecot-lmtpd \
            dovecot-managesieved \
            dovecot-sieve \
            mariadb-server
        _return "Packages"
}

_database_init() {
    echo "${green}Running MariaDB init${reset}"
    ROOT_PW=`_gen_pw`
    for query in "$SQL_ROOT_PW" "$SQL_ROOT_REMOTE" "$SQL_RM_ANON" 
    do
        echo "$query" | mysql
        _return "MariaDB init"
    done
}

_database_postfix() {
        echo "${green}Setting up MariaDB${reset}"
        for query in "$SQL_DB" "$SQL_USER" "$SQL_PERM"
        do
            echo "$query" | mysql
            _return "Database and User creation"
        done

        echo "FLUSH PRIVILEGES" | mysql
        _return "Flushing privileges"


        for query in "$SQL_TBL_DOMAIN" "$SQL_TBL_USERS" "$SQL_TBL_ALIAS"
        do
            echo "$query" | mysql ${DATABASE}
            _return "Table creation"
        done
}

_database_login() {
        echo "quit" | mysql -u${DB_USER} -p"${DB_PASSWORD}" ${DATABASE} 
        _return "Login Test for with User"
}


_cert() {
        #TODO Strictly optional maybe replaced or changed
        # https://pki-ws-rest.symauth.com/mpki/docs/index.html
        #wget -O -  https://get.acme.sh | sh -s postmeister@tricoma.de
        if [ ! -d ~/.acme.sh ]; then
        wget -O -  ${verbose--q} https://get.acme.sh | sh -s email=${EMAIL}
        _return "Download"
        else 
        /root/.acme.sh/acme.sh --register-account -m ${EMAIL} --server letsencrypt
        /root/.acme.sh/acme.sh --issue --standalone -d ${DOMAIN}
        _return "API Call"
        fi

        cp ${verbose--v} /root/acme.sh/${DOMAIN}/${DOMAIN}.key \
        /etc/ssl/private/mailserver.key
        _return "Copy Keyfile for $DOMAIN"
        cp ${verbose--v}  /root/acme.sh/${DOMAIN}/fullchain.cer \
        /etc//ssl/private/
        _return "Copy Cert for $DOMAIN"
}

_postfix() {
        echo "${green}Setting up Postfix/SMTP Server${reset}"

        usermod -a -G mysql postfix
        _return "Add Postfix User to mysql group"

        echo "/var/run/mysqld\t/var/spool/postfix/var/run/mysqld/\tnone\tbind" \ 
        >> /etc/fstab
        _return "Adding fstab entry"

        mount -a
        _return "Mounting MySQL Socket"

        sed -e 's/${DOMAIN}/'$DOMAIN'/g' postfix/main.cf > /etc/postfix/main.cf
        sed -e 's/${HOSTNAME}/'$HOSTNAME'/g' postfix/main.cf > /etc/postfix/main.cf

        mkdir -p /etc/postfix/local
        
        for file in local/*.cf
        do
            sed -e 's;${DB_PASSWORD};'$DB_PASSWORD';g' $file > /etc/postfix/$file
            _return "Replace String in $file"
        done 
        
        cp postfix/master.cf /etc/postfix/
        _return "Copy master.cf"
}

_dovecot() {
        echo "${green}Setting up Dovecot/IMAP Server${reset}"

        groupadd --system --gid ${GID} vmail
        _return "Add Group"

        adduser --system --gid ${GID} --uid ${GID} vmail \
        --disabled-login --disabled-password --home /var/vmail
        _return "Add User"

        mv ${verbose--v} /etc/dovecot /etc/dovecot_default
        _return "Renaming Dovcot Directory"

        cp -r ${verbose--v} dovecot /etc/
        _return "Copy Dovcot install files to /etc"

         sed -i -e 's;${DB_PASSWORD};'$DB_PASSWORD';g' \
        /etc/dovecot/dovecot-sql-conf.ext 

}

if [ `id -u` ]; then
    if [ -f /root/.bootstraped ]; then
        echo "${red}Sorry, please check Host - seems already bootstraped.${reset}"
    else
        echo "`date`\n${DB_USER}:${DB_PASSWORD}\nroot:${DB_ROOT_PASSWORD}" \
        > ~/.bootstraped
       #_update
       #_packages
       #_database_init
       #_database_postfix
       #_database_login
       #_cert
       #_postfix
       #_dovecot
        echo "${green}Installation finished${reset}"
    fi
else
    echo "${red}Must be root to run this skript${reset}"
fi


