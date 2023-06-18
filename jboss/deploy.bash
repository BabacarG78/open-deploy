#!/bin/ksh



# Variables
DESTINATAIRE_MAIL=FR-ME-GDS@socgen.com
LIGNE_ETOILE="***************************************************************"
DATE=`date +%Y%m%d-%H%M`
BASE_DIR=`pwd`
LOGS_DIR="$BASE_DIR/logs"
LOG_SCRIPTS="$LOGS_DIR/script_install_gds-$DATE.log"
LIST_SERVERS_TO_DEPLOY_ON=""
mkdir -p $LOGS_DIR
# nettoyage si le log existe déjà
rm -f $LOG_SCRIPTS

function traiterRetour()
{
    RET=$1
    echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
    if [ $RET -gt 0 ]
    then
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        MESSAGE_ERREUR="Une erreur s'est produite lors du deploiement, consultez les logs." 
        echo "$MESSAGE_ERREUR" | tee -a $LOG_SCRIPTS
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        echo -e "Bonjour,\n\n"$MESSAGE_ERREUR"\nCdt" | mail -s "[ $ENVIRONNEMENT  ] Deploiement de la $VERSION sur $HOSTNAME" $DESTINATAIRE_MAIL
        exit 25
    else
        echo "Deploiement termine sans erreur sur $2" | tee -a $LOG_SCRIPTS
    fi
}

function getLastestVersion(){
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
		elif test ! -z "$LAST_UPDATED_RELEASE"
		then
			URL_VERSION=$MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml
			URL_LIVRABLE_DISTANT=$URL_GET_RELEASE
		else
			printf "Version $VERSION inconnue \n\n" | tee -a $LOG_SCRIPTS
			exit 1
		fi
	fi
	printf "Utilisation de la version $VERSION\n\n" | tee -a $LOG_SCRIPTS
	return $VERSION
}