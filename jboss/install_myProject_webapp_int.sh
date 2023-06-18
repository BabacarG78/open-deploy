#!/bin/bash

#################################################################
# Pegase : installation de l'application web                   #
# Parametre 1 facultatif : version (latest)                     #
#################################################################

# Jboss directories
JBOSS_HOME="/usr/local/apps/wildfly"
DEPLOY_DIR="/tmp/pegase"
# Script work directories
LIVRABLE_TEMP_DIR="/tmp/pegase"
MAVEN_METADATA_SNAPSHOT_DIR="$LIVRABLE_TEMP_DIR/snapshot"
MAVEN_METADATA_RELEASE_DIR="$LIVRABLE_TEMP_DIR/release"
LOG_SCRIPTS="$LIVRABLE_TEMP_DIR/script_install_pegase.log"

# Nexus URLs
URL_NEXUS="http://s-nexus-qua-01:8081/nexus/content/repositories"
URL_NEXUS_SNAPSHOT="$URL_NEXUS/snapshots/com/de/pegase"
URL_NEXUS_RELEASE="$URL_NEXUS/releases/com/de/pegase"
URL_GET_SNAPSHOT="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=snapshots&g=com.de&a=pegase-webapp&e=war&v="
URL_GET_RELEASE="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=releases&g=com.de&a=pegase-webapp&e=war&v="


# Pegase vars
PHOENIX_URL=http://localhost:8080/pegase
PHOENIX_DEST_FILENAME=pegase.html

function check_deplyment(){
	URL="http://localhost:8080/pegase"
	HOME_PAGE="pegase_home_page.html"
	wget -nv -O$LIVRABLE_TEMP_DIR/$HOME_PAGE $URL
	VERSION_DEPLOYED=`cat /tmp/pegase/pegase_home_page.html | grep -oPz "<span.*>Version :(?s).*?</span>" | grep -oPz "([0-9]|[.])+(-SNAPSHOT)*"`
	printf "Version deployer sur $HOSTNAME : $VERSION_DEPLOYED\n\n" | tee -a $LOG_SCRIPTS
	if [ "$VERSION" == "$VERSION_DEPLOYED" ]
	then
		echo -e "Bonjour,\n\nInstallation termine sur $HOSTNAME ,\n\n Version deployee $VERSION_DEPLOYED \n\n Cdt" | mail -s "[ $ENV_TYPE ] Rapport d'installation sur $HOSTNAME" $DESTINATAIRE_MAIL
	else
		echo -e "Bonjour,\n\nErreur lors de l'installation sur $HOSTNAME.\n\n Veuillez consulter les logs \n\nCdt" | mail -s "[ $ENV_TYPE ] Rapport d'installation sur $HOSTNAME" $DESTINATAIRE_MAIL
		exit 1
	fi
}

# Others
LIGNE_ETOILE="*******************************************************************************************"
rm -f $LOG_SCRIPTS

# Verification si la variable d'environnement JBOSS_DE existe pour l'utiliser dans le script
if [ -z "$JBOSS_DE" ]
then
	echo "Variable d'environnement JBOSS_DE non definie" | tee -a $LOG_SCRIPTS
	JBOSS_SERVER_DIR=$JBOSS_DEFAULT_SERVER_DIR
else
	echo "Variable d'environnement JBOSS_DE definie" | tee -a $LOG_SCRIPTS
	JBOSS_SERVER_DIR=$JBOSS_DE
fi
echo "Utilisation du repertoire JBoss $JBOSS_SERVER_DIR" | tee -a $LOG_SCRIPTS

#Determination des variables mails
MESSAGE_DEBUT="Le deploiement de Pegase va demarrer sur $HOSTNAME."
DESTINATAIRE_MAIL_NO_PROD=int-dosi-souscription-tech@poweo-direct-energie.com
DESTINATAIRE_MAIL_PROD=int-dosi-souscription-deploiement@poweo-direct-energie.com
ENV_TYPE=`cat /etc/profile.d/env_DE.sh | grep ENV_TYPE | awk 'BEGIN { FS = "\"" } ; { print $2 }'`
expectedEnvTab=( dev int qua qua_tma qua_perfs pre prod )
envTypeOk=""
for envType in ${expectedEnvTab[@]}
do
        if [ "$envType" = "$ENV_TYPE" ]
        then
            envTypeOk="OK"
            echo "Environnement de deploiement defini : ($ENV_TYPE)"
            case $envType in
                dev|int|qua|qua_tma|qua_perfs)
                        DESTINATAIRE_MAIL=$DESTINATAIRE_MAIL_NO_PROD;;
                pre|prod)
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

echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
if test -z "$1"
then
    echo "Recherche de la derniere version sur le depot..." | tee -a $LOG_SCRIPTS
	
	LAST_UPDATED_SNAPSHOT=`cat $MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml | grep -oE "<lastUpdated>[0-9]+</lastUpdated>" | grep -oE [0-9]+`
	LAST_UPDATED_RELEASE=`cat $MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml | grep -oE "<lastUpdated>[0-9]+</lastUpdated>" | grep -oE [0-9]+`
	
	if [ $LAST_UPDATED_RELEASE -gt $LAST_UPDATED_SNAPSHOT ]
	then
		URL_VERSION=$MAVEN_METADATA_RELEASE_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_RELEASE
	else
		URL_VERSION=$MAVEN_METADATA_SNAPSHOT_DIR/maven-metadata.xml
		URL_LIVRABLE_DISTANT=$URL_GET_SNAPSHOT
	fi
	
	VERSION=`cat $URL_VERSION | grep -oE "<version>.+</version>" | tail -1 | grep -oE "[a-zA-Z0-9\\.-]+" | awk 'FNR == 2 {print}'`
else
	echo "Verification de la version saisie..." | tee -a $LOG_SCRIPTS
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
		echo "Version $VERSION inconnue" | tee -a $LOG_SCRIPTS
		exit 1
	fi
fi

#toutes les variables doivent etre affectees
set -o nounset

echo "Utilisation de la version $VERSION" | tee -a $LOG_SCRIPTS
LIVRABLE="$LIVRABLE_TEMP_DIR/pegase-webapp-$VERSION.war"

# Telechargement
rm -f $LIVRABLE_TEMP_DIR/pegase-webapp-$VERSION.war
wget -nv -O$LIVRABLE_TEMP_DIR/pegase-webapp-$VERSION.war "$URL_LIVRABLE_DISTANT$VERSION"
if [ $? -ne 0 ]
then
	echo "Fichier distant $URL_LIVRABLE_DISTANT/$VERSION/pegase-webapp-$VERSION.war indisponible" | tee -a $LOG_SCRIPTS
	exit 2
else
	NAME_ARTEFACT_WITH_TIMESTAMP=`find $LIVRABLE_TEMP_DIR/pegase-webapp-${VERSION%-SNAPSHOT*}*.war`
	mv $NAME_ARTEFACT_WITH_TIMESTAMP $LIVRABLE
fi

echo -e "Bonjour,\n\n"$MESSAGE_DEBUT"\nCdt" | mail -s "[ $ENV_TYPE ] Deploiement de Pegase $VERSION sur $HOSTNAME" $DESTINATAIRE_MAIL
echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS

cd $JBOSS_HOME/bin

wget -nv -O$LIVRABLE_TEMP_DIR/$PHOENIX_DEST_FILENAME $PHOENIX_URL
OLD_VERSION=`cat $LIVRABLE_TEMP_DIR/$PHOENIX_DEST_FILENAME | grep -oPz "<span.*>Version :(?s).*?</span>" | grep -oPz "([0-9]|[.])+(-SNAPSHOT)*"`

echo "Ancienne version deployer  $OLD_VERSION"
echo "Nouvelle version a deployer  $VERSION"

if [ ! -z "$OLD_VERSION" ]
then
	printf "Suppression d' pegase-webapp-$OLD_VERSION.war \n\n" | tee -a $LOG_SCRIPTS
	printf "undeploy pegase-webapp-$OLD_VERSION.war \n\n" | tee -a $LOG_SCRIPTS
	./jboss-cli.sh -c --command="undeploy pegase-webapp-$OLD_VERSION.war"
	sleep 10
fi

echo "Arret / demarrage de JBoss pour eviter les fuites de memoire"

service wildfly restart

sleep 60

echo "jboss-cli.sh --connect --command=\"deploy $LIVRABLE_TEMP_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase.war --force\""
./jboss-cli.sh --connect --command="deploy $LIVRABLE_TEMP_DIR/pegase-webapp-$VERSION.war --runtime-name=pegase.war --force"

cd -

check_deplyment

echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
echo "Installation du livrable pegase-webapp-$VERSION.war" | tee -a $LOG_SCRIPTS

# on purge les repertoires de travail
rm -f $DEPLOY_DIR/*.war
rm -f $LIVRABLE

echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
echo "Installation terminee sur $HOSTNAME" | tee -a $LOG_SCRIPTS
echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
echo "Installation termine sur $HOSTNAME" | mail -s "[ $ENV_TYPE ] Installation de Pegase sur $HOSTNAME" $DESTINATAIRE_MAIL
