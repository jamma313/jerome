#!/bin/bash
#
# syntax :
# zimbra.sh { backup | restore }
#
# (fr)
# Utilisez les droits "root" 
# (en)
# Use "root" privilege
#
# (fr)
# Pour faire le backup : lancer le script avec l'option "backup"
# Pour restorer :
# => décomprésser l'archive zimbra.backup.tar.gz dans "PATH_BACKUP"
# => installer zimbra, avant d'appliquer les confs : modifier les paramétres sauvegardé dans l'archive "mail_gestion.conf"
# => lancer le script avec l'option "restore"
# 
# (en)
# To backup : use this script with "backup" argument
# To restore :
# => decompress zimbra.backup.tar.gz in "PATH_BACKUP"
# => install zimbra, but before applying configurations : set parameters writed in "mail_gestion.conf"
# => use this script with "retore" argument

# Copyright 2013 GON Jérôme 
# (jerome.gon@gmx.fr)
#
# Licence GNU GPLv3 
#
# This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# set this variables, use absoluts links
PATH_ZIMBRA="/opt/zimbra"
PATH_BACKUP="/opt/zimbra_backup"
USER_ZIMBRA="zimbra"
GROUP_ZIMBRA="zimbra"
IP_ancien=""

# Check doubloon
if [ ! -d $PATH_ZIMBRA ]
    then
	echo -e "ERROR : Aucun dossier $PATH_ZIMBRA.\nVérifier le répertoire d'installation de zimbra.\n"
	exit 20
    else

case $1 in
    backup)

	echo -e "\n\t\t########\n\t\t#BACKUP#\n\t\t########\n\n\t###INITIALISATION###\n"

	mkdir -p $PATH_BACKUP/deploy
	chown -R $USER_ZIMBRA:$GROUP_ZIMBRA $PATH_BACKUP

	echo -e "\n###INIT : OK\n\n\t###RECUPERATION DONNEES###\n"

	echo "\n=> LDAP"

# LDAP backup
	su -c "$PATH_ZIMBRA/libexec/zmslapcat -c $PATH_BACKUP" - $USER_ZIMBRA
	su -c "zmprov gacf | grep -i spamis" - $USER_ZIMBRA > $PATH_BACKUP/mail_gestion.conf
       	su -c "zmprov gacf | grep -i quarantine" - $USER_ZIMBRA >> $PATH_BACKUP/mail_gestion.conf
        su -c "zmlocalconfig -s mailboxd_keystore_password" - $USER_ZIMBRA > $PATH_BACKUP/mdp
	su -c "$PATH_ZIMBRA/libexec/zmslapcat $PATH_BACKUP" - $USER_ZIMBRA

# (fr)
#   !! à décommenter si vous n'utilisez pas rsync (cf partie restore) !! 
# (en)
# uncomment if you don't use "rsync"
#	echo "\n=> DONNEES"

# data backup
#	cp -r $PATH_ZIMBRA/db/data/ $PATH_BACKUP
#	cp -r $PATH_ZIMBRA/store/ $PATH_BACKUP
#	cp -r $PATH_ZIMBRA/index/ $PATH_BACKUP
#       cp -r $PATH_ZIMBRA/zimlets-deployed/* $PATH_BACKUP/deploy/

	echo "\n=> CONFIG"

# configurations backup
	cp $PATH_ZIMBRA/conf/localconfig.xml $PATH_BACKUP
	cp $PATH_ZIMBRA/mailboxd/etc/keystore $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/smtpd.crt $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/smtpd.key $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/slapd.crt $PATH_BACKUP
        cp $PATH_ZIMBRA/conf/slapd.key $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/nginx.crt $PATH_BACKUP
        cp $PATH_ZIMBRA/conf/nginx.key $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/amavisd.conf $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/freshclam.conf $PATH_BACKUP
	cp $PATH_ZIMBRA/conf/my.cnf $PATH_BACKUP

	echo -e "\n###SAVE : OK\n\n\t###ARCHIVAGE###\n"

# archiving
	cd $PATH_BACKUP
	tar zcvf /tmp/zimbra.backup.tar.gz *
	cd 
	rm -r $PATH_BACKUP/*
	mv /tmp/zimbra.backup.tar.gz $PATH_BACKUP

	echo -e "\n###ARCHIVAGE : OK\n\n\t###FIN###\narchive du backup : $PATH_BACKUP/zimbra.backup.tar.gz\n"
	exit 0
    ;;

    restore)

        echo -e "\n\t\t#########\n\t\t#RESTORE#\n\t\t#########\n\n\t###INITIALISATION###\n"

# stop zimbra
       /etc/init.d/zimbra stop
       sleep 15 

	echo -e "\n### INIT : OK\n\n\t### PREPARATION NOUVELLE CONFIG\n"
	echo "=> SUPRESSION ANCIENNE CONFIG"

# delete old data and config
	rm -rf $PATH_ZIMBRA/data/ldap/config/*
	rm -rf $PATH_ZIMBRA/data/ldap/hdb/*
	rm -rf $PATH_ZIMBRA/db/data/*

	echo -e "\n=> CREATION NOUVEAUX DOSSIERS"

	mkdir -p $PATH_ZIMBRA/data/ldap/hdb/db $PATH_ZIMBRA/data/ldap/hdb/logs
	chown -R $USER_ZIMBRA:$GROUP_ZIMBRA $PATH_ZIMBRA/data/ldap

	echo -e "### PREPA : OK\n\t\t### MISE EN PLACE\n"
	echo -e "\n=> LDAP"

# restore LDAP
        su -c "$PATH_ZIMBRA/openldap/sbin/slapadd -q -n 0 -F $PATH_ZIMBRA/data/ldap/config -cv -l $PATH_BACKUP/ldap-config.bak" - $USER_ZIMBRA
	su -c "$PATH_ZIMBRA/openldap/sbin/slapadd -q -b \"\" -F $PATH_ZIMBRA/data/ldap/config -cv -l $PATH_BACKUP/ldap.bak" - $USER_ZIMBRA

	echo -e "\n=> CONF"

# build localconfig.xml
	cp $PATH_ZIMBRA/conf/localconfig.xml $PATH_ZIMBRA/conf/localconfig.xml.orig

	LIST="zimbra_mysql_password mysql_root_password mailboxd_truststore_password mailboxd_keystore_base_password zimbra_ldap_password ldap_root_password ldap_postfix_password ldap_amavis_password ldap_nginx_password ldap_replication_password"

	for KEY in $LIST
	do
	    line_bak=$(grep -n $KEY $PATH_BACKUP/localconfig.xml | cut -d ":" -f1 )
	    if [ ! -z "$line_bak" ]
		then
	    		MdP=$(sed -n "$(($line_bak+1))p" $PATH_BACKUP/localconfig.xml)

	                line=$(grep -n $KEY $PATH_ZIMBRA/conf/localconfig.xml | cut -d ":" -f1 )
	    		if [ -z "$line" ]
			    then
				sed -i 4i"<key name=\"$KEY\"> $MdP </key>" $PATH_ZIMBRA/conf/localconfig.xml 
			    else
				sed -i "$(($line+1))c$MdP" $PATH_ZIMBRA/conf/localconfig.xml
	   	     	fi
	    fi
	done

	LIST_SPECIAL="zimbra_logger_mysql_password mailboxd_keystore_password"

	for KEY in $LIST_SPECIAL
	do
	    line_bak=$(grep -n $KEY $PATH_BACKUP/localconfig.xml | cut -d ":" -f1 )
	    line=$(grep -n $KEY $PATH_ZIMBRA/conf/localconfig.xml | cut -d ":" -f1 )
	    if [ -z "$line_bak" ]
		then
		    if [ ! -z "$ligne" ]
		      then
			sed -i "$((line_bak))d" $PATH_ZIMBRA/conf/localconfig.xml
			sed -i "$((line_bak+1))d" $PATH_ZIMBRA/conf/localconfig.xml
			sed -i "$((line_bak+2))d" $PATH_ZIMBRA/conf/localconfig.xml
		    fi
		else
            		MdP=$(sed -n "$(($line_bak+1))p" $PATH_BACKUP/localconfig.xml)

            		if [ -z "$line" ]
                	    then    
                        	sed -i 4i"<key name=\"$KEY\"> $MdP </key>" $PATH_ZIMBRA/conf/localconfig.xml
                	    else    
                        	sed -i "$(($line+1))c<value>$MdP<\/value>" $PATH_ZIMBRA/conf/localconfig.xml
            		fi  
	    fi
        done

	echo -e "\n=> MISE EN PLACE DES NOUVELLES DONNEES"

# restore data
# (fr)
#   !! à décommenter si vous n'utilisez pas rsync (ne pas oublier la partie backup) !! 
# (en)
# uncomment if you don't use "rsync" (don't forget backup part)
#	cp -r $PATH_BACKUP/data $PATH_ZIMBRA/db/
#	cp -r $PATH_BACKUP/store $PATH_ZIMBRA/
#	cp -r $PATH_BACKUP/index $PATH_ZIMBRA/
#	cp -r $PATH_BACKUP/deploy/* $PATH_ZIMBRA/zimlets-deployed/

	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/store/ $PATH_ZIMBRA/store/
	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/index/ $PATH_ZIMBRA/index/
	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/db/ $PATH_ZIMBRA/db/

# retore configuration
	cp $PATH_BACKUP/keystore $PATH_ZIMBRA/mailboxd/etc/
	cp $PATH_BACKUP/smtpd.*	$PATH_ZIMBRA/conf/ 
        cp $PATH_BACKUP/slapd.*	$PATH_ZIMBRA/conf/
        cp $PATH_BACKUP/nginx.* $PATH_ZIMBRA/conf/
        cp $PATH_BACKUP/amavisd.conf $PATH_ZIMBRA/conf/
        cp $PATH_BACKUP/freshclam.conf $PATH_ZIMBRA/conf/
        cp $PATH_BACKUP/my.cnf $PATH_ZIMBRA/conf/

	MdP_Keystore="$(cat $PATH_BACKUP/mdp | cut -d " " -f3)"
        su -c "zmlocalconfig -e mailboxd_keystore_password=$MdP_keystore" - $USER_ZIMBRA

# fix permissions
	chown -R $USER_ZIMBRA:$GROUP_ZIMBRA $PATH_ZIMBRA
	/opt/zimbra/libexec/zmfixperms 

        echo -e "\n### MISE EN PLACE : OK\n\n\t### ALLUMAGE\n"
	killall -u zimbra
	rm /opt/zimbra/openldap/var/run/slapd.pid

# creating certificates
# uncomment to backup/restore original certificates
#	/opt/zimbra/bin/zmcertmgr createca -new 1&2>/dev/null
#	/opt/zimbra/bin/zmcertmgr createcrt -new -days 365 1&2>/dev/null
#	/opt/zimbra/bin/zmcertmgr deploycrt self 1&2>/dev/null
#	/opt/zimbra/bin/zmcertmgr deployca 1&2>/dev/null

# take care of no missing data (comment if you use "cp")
	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/store/ $PATH_ZIMBRA/store/
	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/index/ $PATH_ZIMBRA/index/
	rsync -axv --delete root@$IP_ancien:$PATH_ZIMBRA/db/ $PATH_ZIMBRA/db/

# start zimbra
	/etc/init.d/zimbra start
	sleep 15

        echo -e "\n### ALLUMAGE : OK\n\n\t### DECOLLAGE !\n"
    ;;
    *)
	echo "Usage : zimbra.sh { backup | restore }"
    ;;
esac

fi
