#!/bin/bash

#################################################################
# Pegase : installation de l'application web                   #
# Parametre 1 facultatif : version (latest)                     #
#################################################################

#-------------------------------------------------------------------
#			Variables JBOSS CLI			   #
#-------------------------------------------------------------------
TEMPLATE_SG="/home/jboss/install/pegase/templateServerGroup.cfg"
DOMAIN_CONFIG_DIR="/usr/local/jboss/domain/configuration"
DOMAIN_CONFIG_FILE=$DOMAIN_CONFIG_DIR"/domain.xml"
SERVER_GROUP_NAME="PEGASE_"
OLD_SERVER_GROUP_NAME="PEGASE_"
WAR_DIR="/home/jboss/pegase"
RUNTIME_NAME="pegase-webapp.war"
HOST_INSTANCE=""
JBOSS_DEPLOYMENT="/home/jboss/deploy/pegase"
JBOSS_HOME="/usr/local/jboss"
PATTERN_NOT_FOUND_SG="not found|pas .t. trouv." 
EXISTING_SERVER_GROUP="false"
ERROR_JBOSS_CLI="failed"
heap_size=256m
max_heap_size=512m
permgen_size=256m
max_permgen_size=512m
FLAG="OK"
PORT="8180"
DEFAULT_PORT="8080"
FLAG_DEPLOYMENT_DONE="false"
FLAG_INSTANCE_CREATED="false"
SCRIPT_HOST_STOP=""
SCRIPT_HOST_REMOVE=""

#-----------------------------------------------------------------------
# 			Variables Script Work Directories  		#
#-----------------------------------------------------------------------
LIVRABLE_TEMP_DIR="/home/jboss/pegase"
LIVRABLE="/home/jboss/pegase"
MAVEN_METADATA_SNAPSHOT_DIR="$LIVRABLE_TEMP_DIR/snapshot"
MAVEN_METADATA_RELEASE_DIR="$LIVRABLE_TEMP_DIR/release"
LOG_SCRIPTS="$LIVRABLE_TEMP_DIR/script_install_pegase.log"

#-------------------------------------------------------------------
# 			Variables NEXUS				    #
#-------------------------------------------------------------------
URL_NEXUS="http://s-nexus-qua-01:8081/nexus/content/repositories"
URL_NEXUS_SNAPSHOT="$URL_NEXUS/snapshots/com/de/pegase-webapp"
URL_NEXUS_RELEASE="$URL_NEXUS/releases/com/de/pegase-webapp"
URL_GET_SNAPSHOT="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=snapshots&g=com.de&a=pegase-webapp&e=war&v="
URL_GET_RELEASE="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=releases&g=com.de&a=pegase-webapp&e=war&v="

#-------------------------------------------------------------------
# 			Variables Pegase			    #
#-------------------------------------------------------------------
PEGASE_URL=http://$2/pegase
PEGASE_DEST_FILENAME=pegase.html

#------------------- Nettoyage des fichiers de log et de jboss cli ---------------------#
echo "Nettotage des fichiers de log et de jboss cli ........................"
rm -rf $JBOSS_DEPLOYMENT/*.log
rm -rf $JBOSS_DEPLOYMENT/*.cli

wget -nv -O$LIVRABLE_TEMP_DIR/$PEGASE_DEST_FILENAME $PEGASE_URL
OLD_VERSION=`cat $LIVRABLE_TEMP_DIR/$PEGASE_DEST_FILENAME | grep -oE "<span.*>Version\s:\s.*</span>" | grep -oE "([0-9]|[.])+(-SNAPSHOT)*"`

# Others
LIGNE_ETOILE="***************************************************************************************************************************************"
rm -f $LOG_SCRIPTS
echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
echo "Ancienne version : $OLD_VERSION ................................................\n" | tee -a $LOG_SCRIPTS

function updateDomain(){
  SERVER_GROUP_NAME=$1
  sed "s/SERVER_GROUP_NAME/$SERVER_GROUP_NAME/" $TEMPLATE_SG > /home/jboss/install/pegase/addServerGroup.xml
  echo "Arret de JBoss ...................................................."
  service jboss stop
  cp -f $DOMAIN_CONFIG_FILE $DOMAIN_CONFIG_DIR"/domain_backup.xml"
  sed -i '/<server-groups>/r /home/jboss/install/pegase/addServerGroup.xml' $DOMAIN_CONFIG_FILE
  echo "Demarrage de JBoss ................................................"
  service jboss start &>/dev/null
}

function check_errors(){
        #Tester les actions precedentes
        NB_FAILED=`cat \$LOG_SCRIPTS | grep -oE "failed.*" | sed s/'",'/''/g`
        if [ -n "$NB_FAILED" ]
        then
		printf "*******************************************************************************************************\n\n" | tee -a $LOG_SCRIPTS
        printf "***********	Probleme lors du deploiement veuillez consulter les logs 	        ***************\n\n" | tee -a $LOG_SCRIPTS
		printf "*******************************************************************************************************\n\n" | tee -a $LOG_SCRIPTS
		#Delete All servers group and instance
	        if [ "$FLAG_INSTANCE_CREATED" = "true" ]
            then
				printf "Attente de 60 s avant d'arreter les server nouvellement creer \n\n" | tee -a $LOG_SCRIPTS
				sleep 60
        	    printf "$SCRIPT_HOST_STOP"  | tee -a $LOG_SCRIPTS
				./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_stop_new_server_config.cli > $JBOSS_DEPLOYMENT/script_stop_new_server_config.log
				cat $JBOSS_DEPLOYMENT/script_stop_new_server_config.log
                	
				printf "Attente de 2 mn avant le nettoyage du domain \n\n" | tee -a $LOG_SCRIPTS
				sleep 120
			
	            printf "$SCRIPT_HOST_REMOVE"  | tee -a $LOG_SCRIPTS
				./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_remove_new_server_config.cli > $JBOSS_DEPLOYMENT/script_remove_new_server_config.log         
				cat $JBOSS_DEPLOYMENT/script_remove_new_server_config.log
	
				printf "/server-group=$SERVER_GROUP_NAME_VALUE:remove()\n" | tee -a $LOG_SCRIPTS
				./jboss-cli.sh -c --command="/server-group=$SERVER_GROUP_NAME_VALUE:remove()" > $JBOSS_DEPLOYMENT/nettoyage_deplyment.log	               
				cat $JBOSS_DEPLOYMENT/nettoyage_deplyment.log
            fi
                       
			if [ "$FLAG_DEPLOYMENT_DONE" = "true" ]
			then 
				printf "undeploy pegase-webapp-$VERSION.war --all-relevant-server-groups\n\n" | tee -a $LOG_SCRIPTS
				./jboss-cli.sh -c --command="undeploy pegase-webapp-$VERSION.war --all-relevant-server-groups" > $JBOSS_DEPLOYMENT/nettoyage_deplyment.log	               
				cat $JBOSS_DEPLOYMENT/nettoyage_deplyment.log
			fi
                cat $LOG_SCRIPTS | mail -s "[ $ENV_TYPE  ] Erreur lors de l'installation de Pegase veuillez consulter les logs" $DESTINATAIRE_MAIL
                exit 2
        fi
}


function check_existing_server_group(){	
	#Verification de l'existence d'un server-group
	printf "Verification de l existence du server-group : $OLD_SERVER_GROUP_NAME$OLD_VERSION .................\n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="cd server-group=$OLD_SERVER_GROUP_NAME$OLD_VERSION" > $JBOSS_DEPLOYMENT/exists_server_group.log
	grep -oE "$PATTERN_NOT_FOUND_SG" $JBOSS_DEPLOYMENT/exists_server_group.log &>/dev/null
 	
 	rc=$?
    if [[  $rc != 0 ]]
	then
		printf "Le server-group : $OLD_SERVER_GROUP_NAME$OLD_VERSION est bien exitant ..................\n\n" | tee -a $LOG_SCRIPTS
		EXISTING_SERVER_GROUP="true"
	else
		printf "Le server-group $OLD_SERVER_GROUP_NAME$OLD_VERSION : n existe pas.............................\n\n" | tee -a $LOG_SCRIPTS
		FLAG="KO"
	fi
}

function get_port_offset(){
	server=$1
	current_version=$2
	old_version=$3
	if [ "$EXISTING_SERVER_GROUP" = "true" ]
	then
		./jboss-cli.sh -c --command="/host=$server:read-children-resources(child-type=server-config) > $JBOSS_DEPLOYMENT/$server.log"	
		OLD_SERVER_INSTANCE=`cat \$JBOSS_DEPLOYMENT/\$server.log | grep -oE '"name" => .*'  | grep -oE \$server.* | sed s/'",'/''/g`
	fi	
	if [ ! "$FLAG" = "KO" ]
	then 		
		./jboss-cli.sh -c --command="/host=$server/server-config=$OLD_SERVER_INSTANCE:read-attribute(name=socket-binding-port-offset) > $JBOSS_DEPLOYMENT/result_port_offset.log"
		printf "Recuperation de la valeur du port offset d'une instance du server group existant\n\n" | tee -a $LOG_SCRIPTS
		OFFSET_PORT=`cat \$JBOSS_DEPLOYMENT/result_port_offset.log | grep -oE '"result" => .*' | grep -oE "([0-9]|[.])*"`
		if [ "$OFFSET_PORT" = "0" ]
		then
			printf "Ancienne valeur de port offset : 0\n\n" | tee -a $LOG_SCRIPTS
			OFFSET_PORT_VALUE="100"
		fi	
		FLAG="KO"
	fi
	#Verification des version deployees
	if [ "$OLD_VERSION" == "$VERSION" ]
	then
		PORT=$(($DEFAULT_PORT + $OFFSET_PORT))
	else
		PORT=$(($DEFAULT_PORT + $OFFSET_PORT_VALUE))
	fi
}

function check_deployment(){
	#Verification des version deployees
	server=$1
	URL="http://$server:$PORT/pegase"
	HOME_PAGE=$server".html"
	wget -nv -O$LIVRABLE/$HOME_PAGE $URL 
	VERSION_DEPLOYED=`cat $LIVRABLE_TEMP_DIR/$HOME_PAGE | grep -oPz "<span.*>Version :(?s).*?</span>" | grep -oPz "([0-9]|[.])+(-SNAPSHOT)*"`
	printf "Version deployer sur $server : $VERSION_DEPLOYED\n\n" | tee -a $LOG_SCRIPTS
	if [ "$VERSION" == "$VERSION_DEPLOYED" ]
	then
		echo -e "Bonjour,\n\nInstallation termine sur $server,\n\n Version deployee $VERSION_DEPLOYED \n\n Cdt" | mail -s "[ $ENV_TYPE  ] Rapport d'installation sur $server" $DESTINATAIRE_MAIL	
	else
		echo -e "Bonjour,\n\nErreur lors de l'installation sur $server.\n\n Veuillez consulter les logs \n\nCdt" | mail -s "[ $ENV_TYPE  ] Rapport d'installation sur $server" $DESTINATAIRE_MAIL	
		exit 1
	fi
}
#-----------------------------------------------------------------------
#			Determination des variables mails   		#
#-----------------------------------------------------------------------
MESSAGE_DEBUT="Le deploiement de Pegase va demarrer sur $HOSTNAME."
DESTINATAIRE_MAIL_NO_PROD=int-dosi-souscription-tech@poweo-direct-energie.com
DESTINATAIRE_MAIL_PROD=int-dosi-souscription-deploiement@poweo-direct-energie.com

ENV_TYPE=`cat /etc/profile.d/env_DE.sh | grep ENV_TYPE | awk 'BEGIN { FS = "\"" } ; { print $2 }'`
expectedEnvTab=( qua qua_tma qua_perfs pre prod )
envTypeOk=""
for envType in ${expectedEnvTab[@]}
do
        if [ "$envType" = "$ENV_TYPE" ]
        then
            envTypeOk="OK"
            echo "Environnement de deploiement defini : ($ENV_TYPE)"
            case $envType in
                int|qua|qua_tma|qua_perfs)
                        DESTINATAIRE_MAIL=$DESTINATAIRE_MAIL_NO_PROD;;
                pre|prod)
                		heap_size=512m
                		max_heap_size=1024m
						DESTINATAIRE_MAIL=$DESTINATAIRE_MAIL_PROD;;
                esac
            break
        fi
done
if [ ! "$envTypeOk" = "OK" ]
then
	echo "Le type d'environnement ($ENV_TYPE) doit faire partie de la liste suivante : ${expectedEnvTab[*]}"
	exit 1
fi

# Verification du parametre version
rm -f $MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml
rm -f $MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml
wget -P$MAVEN_METADATA_SNAPSHOT_DIR $URL_NEXUS_SNAPSHOT/maven-metadata.xml -nv
wget -P$MAVEN_METADATA_RELEASE_DIR $URL_NEXUS_RELEASE/maven-metadata.xml -nv

if test -z "$1"
then
    printf "Recherche de la derniere version sur le depot...\n\n" | tee -a $LOG_SCRIPTS	
	LAST_UPDATED_SNAPSHOT=`cat $MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml | grep -oE "<lastUpdated>[0-9]+</lastUpdated>" | grep -oE [0-9]+`
	LAST_UPDATED_RELEASE=`cat $MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml | grep -oE "<lastUpdated>[0-9]+</lastUpdated>" | grep -oE [0-9]+`
	
	if [ $LAST_UPDATED_RELEASE -gt $LAST_UPDATED_SNAPSHOT ]
	then
		URL_VERSION=$MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_RELEASE
		URL_DOC_LISTENER_LIVRABLE_DISTANT=$URL_DOC_LISTENER_GET_RELEASE
	else
		URL_VERSION=$MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_SNAPSHOT
		URL_DOC_LISTENER_LIVRABLE_DISTANT=$URL_DOC_LISTENER_GET_SNAPSHOT
	fi
	VERSION=`cat $URL_VERSION | grep -oE "<version>.+</version>" | tail -1 | grep -oE "[a-zA-Z0-9\\.-]+" | awk 'FNR == 2 {print}'`
else
	printf "Verification de la version saisie... \n\n" | tee -a $LOG_SCRIPTS
    VERSION=$1
	
	LAST_UPDATED_SNAPSHOT=`cat $MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml | grep -o "<version>$VERSION</version>" | grep -o $VERSION`
	LAST_UPDATED_RELEASE=`cat $MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml | grep -o "<version>$VERSION</version>" | grep -o $VERSION`
	
	if test ! -z "$LAST_UPDATED_SNAPSHOT"
	then
		URL_VERSION=$MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_SNAPSHOT
		URL_DOC_LISTENER_LIVRABLE_DISTANT=$URL_DOC_LISTENER_GET_SNAPSHOT
	elif test ! -z "$LAST_UPDATED_RELEASE"
	then
		URL_VERSION=$MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_RELEASE
		URL_DOC_LISTENER_LIVRABLE_DISTANT=$URL_DOC_LISTENER_GET_RELEASE
	else
		printf "Version $VERSION inconnue \n\n" | tee -a $LOG_SCRIPTS
		exit 1
	fi
fi

#toutes les variables doivent etre affectees
set -o nounset

printf "Utilisation de la version $VERSION\n\n" | tee -a $LOG_SCRIPTS

# Telechargement
printf "Repertoire temporaire des livrables :  $LIVRABLE\n\n" | tee -a $LOG_SCRIPTS
printf "Nettoyage de l'ancien livrables pegase-webapp ..................................\n\n" | tee -a $LOG_SCRIPTS
rm -rf $LIVRABLE/*.war

#Telechargement de pegase-webapp
printf "Telechargement du livrable pegase-webapp-$VERSION.war ..................................\n\n" | tee -a $LOG_SCRIPTS
wget -nv -O pegase-webapp-$VERSION.war -P$LIVRABLE_TEMP_DIR $URL_LIVRABLE_DISTANT$VERSION
if [ $? -ne 0 ]
then
	printf "Fichier distant $URL_LIVRABLE_DISTANT/$VERSION/pegase-webapp-$VERSION.war indisponible \n\n" | tee -a $LOG_SCRIPTS
	exit 2
else
	mv pegase-webapp-$VERSION.war $LIVRABLE
fi


echo -e "Bonjour,\n\n"$MESSAGE_DEBUT"\nCdt" | mail -s "[ $ENV_TYPE  ] Deploiement de Pegase $VERSION sur $HOSTNAME" $DESTINATAIRE_MAIL

cd $JBOSS_HOME/bin

typeset SERVERS=(`echo $3 | sed s/'_'/' '/g`)
OFFSET_PORT_VALUE="0"
SERVER_GROUP_NAME_VALUE=$SERVER_GROUP_NAME$VERSION

check_existing_server_group

if test -z "$OLD_VERSION"
then
	echo "Aucune version installe !!!"
	get_port_offset ${SERVERS[0]} $VERSION "NAN"
else
	echo "version installe $VERSION"
	get_port_offset ${SERVERS[0]} $VERSION $OLD_VERSION 
fi

if [ "$OLD_VERSION" == "$VERSION" ]
then
	printf "Suppression d' pegase-webapp-$VERSION.war du server-group : $OLD_SERVER_GROUP_NAME$OLD_VERSION\n\n" | tee -a $LOG_SCRIPTS
	printf "undeploy pegase-webapp-$VERSION.war --server-groups=$OLD_SERVER_GROUP_NAME$OLD_VERSION\n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="undeploy pegase-webapp-$VERSION.war --server-groups=$OLD_SERVER_GROUP_NAME$OLD_VERSION" > $JBOSS_DEPLOYMENT/undeploy.log
	cat $JBOSS_DEPLOYMENT/undeploy.log | tee -a $LOG_SCRIPTS
		
	#Tester les actions precedentes
	check_errors
	
	for server in ${SERVERS[*]}; do
		printf "Redemarrage du server $server-$VERSION du server-group : $OLD_SERVER_GROUP_NAME$OLD_VERSION \n\n" | tee -a $LOG_SCRIPTS
		printf "/host=$server/server-config=$server-$VERSION:restart \n\n" | tee -a $LOG_SCRIPTS
		./jboss-cli.sh -c --command="/host=$server/server-config=$server-$VERSION:restart" > $JBOSS_DEPLOYMENT/restart_servers.log
		cat $JBOSS_DEPLOYMENT/restart_servers.log | tee -a $LOG_SCRIPTS
		#Tester les actions precedentes
		check_errors
	done

	printf "Deploiement d' pegase-webapp-$VERSION.war du server-group $OLD_SERVER_GROUP_NAME$OLD_VERSION \n\n" | tee -a $LOG_SCRIPTS
	printf "deploy $WAR_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase-webapp.war --server-groups=$OLD_SERVER_GROUP_NAME$OLD_VERSION > $JBOSS_DEPLOYMENT/deployment_pegase.log\n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="deploy $WAR_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase-webapp.war --server-groups=$OLD_SERVER_GROUP_NAME$OLD_VERSION" > $JBOSS_DEPLOYMENT/deployment_pegase.log
	cat $JBOSS_DEPLOYMENT/deployment_pegase.log | tee -a $LOG_SCRIPTS

	#Tester les actions precedentes
	check_errors

	#Verification des version deployees
	for server in ${SERVERS[*]}; do
		check_deployment $server
	done	
else
	for server in ${SERVERS[*]}; do	
		if [ "$EXISTING_SERVER_GROUP" = "true" ]
		then
			./jboss-cli.sh -c --command="/host=$server:read-children-resources(child-type=server-config) > $JBOSS_DEPLOYMENT/$server.log"	
			OLD_SERVER_INSTANCE=`cat \$JBOSS_DEPLOYMENT/\$server.log | grep -oE '"name" => .*'  | grep -oE \$server.* | sed s/'",'/''/g`
			OLD_HOST_CMD_STOP+="/host=$server/server-config=$OLD_SERVER_INSTANCE:stop\n\n"
			OLD_HOST_CMD_REMOVE+="/host=$server/server-config=$OLD_SERVER_INSTANCE:remove()\n\n"
		fi	
 
		HOST_INSTANCE+="/host=$server/server-config=$server-$VERSION:add(group=$SERVER_GROUP_NAME_VALUE,auto-start=true,socket-binding-group=full-ha-sockets,socket-binding-port-offset=$OFFSET_PORT_VALUE)\n\n/host=$server/server-config=$server-$VERSION/jvm=default:add(heap-size=$heap_size, max-heap-size=$max_heap_size, permgen-size=$permgen_size, max-permgen-size=$max_permgen_size)\n\n"
				
		HOST_CMD_START+="/host=$server/server-config=$server-$VERSION:start\n\n/host=$server:reload(restart-servers=false)\n\n"
        SCRIPT_HOST_STOP+="/host=$server/server-config=$server-$VERSION:stop()\n\n"
        SCRIPT_HOST_REMOVE+="/host=$server/server-config=$server-$VERSION:remove()\n\n"
	done
	
	cd -

	# Generation des scripts de jboss-cli
	printf "\nGeneration des scripts Jboss CLI ...........................\n\n" | tee -a $LOG_SCRIPTS
	printf "$HOST_INSTANCE" > $JBOSS_DEPLOYMENT/script_config_jboss.cli
	printf "$HOST_CMD_START" > $JBOSS_DEPLOYMENT/script_start_servers.cli

	printf "$SCRIPT_HOST_STOP" > $JBOSS_DEPLOYMENT/script_stop_new_server_config.cli
	printf "$SCRIPT_HOST_REMOVE" > $JBOSS_DEPLOYMENT/script_remove_new_server_config.cli	

	# Si pas de server group initialement on a rien a arreter ni supprimer : donc pas de generation de commande associe
	if [ "$EXISTING_SERVER_GROUP" = "true" ]
	then
		printf "$OLD_HOST_CMD_STOP" > $JBOSS_DEPLOYMENT/script_stop_old_servers.cli
		printf "$OLD_HOST_CMD_REMOVE" > $JBOSS_DEPLOYMENT/script_remove_old_config.cli
	else
		printf "Pas de generation de commande jboss-cli associe a l arret et a la suppression des instances\n\n" | tee -a $LOG_SCRIPTS
	fi

	# Debut d'execution des scripts Jboss-cli 
	cd $JBOSS_HOME/bin
	printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
	printf "#----------------		Creation du server-group et des instances 	$SERVER_GROUP_NAME_VALUE -------------\n" | tee -a $LOG_SCRIPTS

	updateDomain $SERVER_GROUP_NAME_VALUE
	
	printf "#Attente de 1 mn avant d executer les scripts jboss cli\n\n" | tee -a $LOG_SCRIPTS
	sleep 60

	printf "$HOST_INSTANCE" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_config_jboss.cli > $JBOSS_DEPLOYMENT/script_config_jboss.log
	cat $JBOSS_DEPLOYMENT/script_config_jboss.log | tee -a $LOG_SCRIPTS

	#Tester les actions precedentes
	FLAG_INSTANCE_CREATED="true"
	check_errors
	
	printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
	printf "#----------------   Demarrage des instances	 $SERVER_GROUP_NAME_VALUE	---------------------------\n" | tee -a $LOG_SCRIPTS
	printf "$HOST_CMD_START" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_start_servers.cli > $JBOSS_DEPLOYMENT/script_start_servers.log 
	cat $JBOSS_DEPLOYMENT/script_start_servers.log | tee -a $LOG_SCRIPTS
	
	#Tester les actions precedentes
	FLAG_INSTANCE_CREATED="true"
	check_errors

	printf "Attente de 60s avant le debut du deploiement pegase-webapp-$VERSION.war........\n\n" | tee -a $LOG_SCRIPTS
	sleep 60 
	printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
	printf "#----------------	       Deploiement de l artefacts : pegase-webapp-$VERSION.war      \n" | tee -a $LOG_SCRIPTS
	printf "#--------------------------------------------------------------------------------------------------\n\n" | tee -a $LOG_SCRIPTS
	printf "deploy $WAR_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase-webapp.war --server-groups=$SERVER_GROUP_NAME_VALUE \n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="deploy $WAR_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase-webapp.war --server-groups=$SERVER_GROUP_NAME_VALUE" > $JBOSS_DEPLOYMENT/deployment_pegase.log 
	cat $JBOSS_DEPLOYMENT/deployment_pegase.log | tee -a $LOG_SCRIPTS
	

	#Tester les actions precedentes
	FLAG_DEPLOYMENT_DONE="true"
	check_errors

	printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
	printf "#----------------------------    Deploiement de Jolokia 	----------------------------------------\n" | tee -a $LOG_SCRIPTS
	
	printf "Attente de 5s avant le debut du deploiement jolokia-war-1.2.0.war ........\n\n" | tee -a $LOG_SCRIPTS
	sleep 5
	printf "Deploiement de l artefacts : jolokia-war-1.2.0.war  .....................................................\n\n" | tee -a $LOG_SCRIPTS
	printf "deploy --name=jolokia-war-1.2.0.war  --server-groups=$SERVER_GROUP_NAME_VALUE\n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="deploy --name=jolokia-war-1.2.0.war  --server-groups=$SERVER_GROUP_NAME_VALUE" > $JBOSS_DEPLOYMENT/deployment_jolokia.log
	cat $JBOSS_DEPLOYMENT/deployment_jolokia.log | tee -a $LOG_SCRIPTS

	#Verification des version deployees
	for server in ${SERVERS[*]}; do
		check_deployment $server
	done

	if [ "$EXISTING_SERVER_GROUP" = "true" ]
	then
		printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
		printf "#-----------------------------	Undeployment de l'ancien artefacts --------------------------------\n" | tee -a $LOG_SCRIPTS
		printf "undeploy pegase-webapp-$OLD_VERSION.war --all-relevant-server-groups\n\n" | tee -a $LOG_SCRIPTS
		./jboss-cli.sh -c --command="undeploy pegase-webapp-$OLD_VERSION.war --all-relevant-server-groups"
		
		printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
		printf "#---------------------------   Arret des anciens servers  $OLD_SERVER_GROUP_NAME$OLD_VERSION  ----------------\n" | tee -a $LOG_SCRIPTS
		printf "$OLD_HOST_CMD_STOP" | tee -a $LOG_SCRIPTS
		./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_stop_old_servers.cli > $JBOSS_DEPLOYMENT/script_stop_old_servers.log 
		cat $JBOSS_DEPLOYMENT/script_stop_old_servers.log | tee -a $LOG_SCRIPTS
		printf "Attente de 180 s avant la suppression des anciennes instances de servers\n\n"
	
		sleep 180 

		printf "#--------------------------------------------------------------------------------------------------\n" | tee -a $LOG_SCRIPTS
		printf "#-----------------             Suppression des anciennes servers instance $OLD_SERVER_GROUP_NAME$OLD_VERSION \n" | tee -a $LOG_SCRIPTS
		printf "$OLD_HOST_CMD_REMOVE" | tee -a $LOG_SCRIPTS
		./jboss-cli.sh -c --file=$JBOSS_DEPLOYMENT/script_remove_old_config.cli > $JBOSS_DEPLOYMENT/script_remove_old_config.log 
		cat $JBOSS_DEPLOYMENT/script_remove_old_config.log | tee -a $LOG_SCRIPTS

		printf "Suppression du server group $OLD_SERVER_GROUP_NAME$OLD_VERSION..............\n\n" | tee -a $LOG_SCRIPTS
		printf "/server-group=$OLD_SERVER_GROUP_NAME$OLD_VERSION:remove()\n\n" | tee -a $LOG_SCRIPTS
		./jboss-cli.sh -c --command="/server-group=$OLD_SERVER_GROUP_NAME$OLD_VERSION:remove()" | tee -a $LOG_SCRIPTS
	
	fi

	cd -

	echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS

fi

cat $LOG_SCRIPTS | mail -s "[ $ENV_TYPE  ] Rapport sur l'installation de Pegase depuis $HOSTNAME" $DESTINATAIRE_MAIL
rm -f $WAR_DIR/*.war