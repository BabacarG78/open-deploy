#!/bin/bash

function containsElement ()
{
    for e in "${@:2}"; do
        if [ "$e" = "$1" ]; then
            echo "0" | tee -a $LOG_SCRIPTS
            return 0
        fi
    done
    echo "1" | tee -a $LOG_SCRIPTS
    return 0
}

##################################
# MYPROJECT: install generale     #
##################################
DESTINATAIRE_MAIL=devs@open-it@sn
LIGNE_ETOILE="***************************************************************"
DATE=`date +%Y%m%d-%H%M`
BASE_DIR=`pwd`
LOGS_DIR="$BASE_DIR/logs"
LOG_SCRIPTS="$LOGS_DIR/script_install_myProject-$DATE.log"
LIST_SERVERS_TO_DEPLOY_ON=""

mkdir -p $LOGS_DIR
# nettoyage si le log existe déjà
rm -f $LOG_SCRIPTS

# Verification des parametres
if test -z "$1"
then
    echo "Aucun numero de version n'est fourni." | tee -a $LOG_SCRIPTS
    exit 10
else
    echo "Numero de version : $1" | tee -a $LOG_SCRIPTS
fi
VERSION=$1
#- Verification de la presence d'un type d'environnement
if test -z "$2"
then
    echo "Aucun type d'environnement n'est fourni" | tee -a $LOG_SCRIPTS
    exit 15
else
    expectedEnvTab=( int qua pre prod )
    envTypeOk=""
    for envType in ${expectedEnvTab[@]}
    do
        if [ "$envType" = "$2" ]
        then
            envTypeOk="OK"
            echo "Environnement defini : $2" | tee -a $LOG_SCRIPTS
            break
        fi
    done
fi
if [ ! "$envTypeOk" = "OK" ]
then
    echo "Le type d'environnement ($2) doit faire partie de la liste suivante : ${expectedEnvTab[*]}" | tee -a $LOG_SCRIPTS
    exit 20
fi
ENVIRONNEMENT=$2

set -o nounset

#############################################################################################
#                       preparation des noms des variables en fonction de l'environnement   #
#############################################################################################

case "$envType" in
"int")
    server=s-myProject-int-01
    nodes=(s-myProject-int-01)
    BATCH="s-starbatch-qua"
    APACHE=""
    SCRIPT_BATCH=""
    SERVER_SAMBA=""
    SHARED_DIR=""       
    ;;
"qua")
    server=s-jb7-admin-qua
    nodes=(s-myProject-qua-01.de.lan s-myProject-qua-02.de.lan)
    BATCH="s-starbatch-qua"
    APACHE="myProject-qua.open-it.sn"
    SCRIPT_BATCH="install_myProject_batch_trunk.sh"
    SERVER_SAMBA="s-deploy-qua"
    SHARED_DIR="/usr/local/apps/server/DE-all/log/"
    ;;
"pre")
    server=s-jb7-admin-pp
    nodes=(s-myProject-pp-01.de.lan s-myProject-pp-02.de.lan)
    BATCH="s-starbatch-pp"
    APACHE="myProject-pp.open-it.sn"
    SCRIPT_BATCH=""
    SERVER_SAMBA="s-deploy-01"
    SHARED_DIR="/jboss-logs-PRE"    
    ;;
"prod")
    server=s-jb7-admin
    nodes=(s-myProject-01.de.lan s-myProject-02.de.lan)
    BATCH="s-starbatch-01"
    APACHE="myProject.open-it.sn"
    SCRIPT_BATCH=""
    SERVER_SAMBA="s-deploy-01"
    SHARED_DIR="/jboss-logs-PRD"    
    ;;
esac

clear
echo "Les logs de l'installation seront ecrit dans $LOG_SCRIPTS" | tee -a $LOG_SCRIPTS

MODE_INTERACTIF=$( containsElement "-f" $@ )

if [ "$MODE_INTERACTIF" = "1" ]
then
    echo "Mode interactif active" | tee -a $LOG_SCRIPTS
else
    echo "Mode interactif desactive" | tee -a $LOG_SCRIPTS
fi
#############################################################################################
#                    fin preparation des noms des variables en fonction de l'environnement  #
#############################################################################################

#############################################################################################
#                      verification de la disponibilite des ressources  a deployer          #
#############################################################################################
function verifier_entete_livrables()
{
    URL_GET_RELEASE="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=releases&g=com.de&a=myProject&e=war&v="
    URL_GET_SNAPSHOT="http://s-nexus-qua-01:8081/nexus/service/local/artifact/maven/redirect?r=snapshots&g=com.de&a=myProject&e=war&v="
    SNAPSHOT=`echo $VERSION | grep SNAPSHOT`
    if [ -z $SNAPSHOT ]
    then
        URL_LIVRABLE_DISTANT=$URL_GET_RELEASE
    else
        URL_LIVRABLE_DISTANT=$URL_GET_SNAPSHOT
    fi
    
    #chargement des entetes du livrable: si on a un code http 301, on est sur la page de redirection de Nexus -> c'est OK.
    HTTP_HEADER=`curl  --head   "$URL_LIVRABLE_DISTANT$VERSION"  2>&1 | grep HTTP| awk {'print $2'} `
    if [ $HTTP_HEADER = 404 ]
    then
        echo "Fichier distant $URL_LIVRABLE_DISTANT/$VERSION/myProject-$VERSION.war indisponible"  | tee -a $LOG_SCRIPTS
        exit 2
    elif [[ "$HTTP_HEADER" =~ ^30[1278]$ ]] # tous les codes de redirections (301/302/307/308)
    then
        #recuperation de l'emplacement du war
        HTTP_WAR_LOCATION=`curl  --head   "$URL_LIVRABLE_DISTANT$VERSION"  2>&1 | grep Location | awk {'print $2'} `
        #suppression d'un caractere bloquant 
        HTTP_WAR_LOCATION_CORRIGE=`echo $HTTP_WAR_LOCATION |awk 'BEGIN { FS = "war" } ; { print $1 }'`
        HTTP_FINAL_LOCATION=$HTTP_WAR_LOCATION_CORRIGE\war
        HTTP_FINAL_HEADER=`curl  --head   "$HTTP_FINAL_LOCATION"  2>&1 | grep HTTP | awk {'print $2'}`
        if [ $HTTP_FINAL_HEADER = 200 ]
        then
            echo "le war Pegase $VERSION est bien present sur Nexus.Le deploiement se poursuit." | tee -a $LOG_SCRIPTS
        else
            echo "Fichier distant $URL_LIVRABLE_DISTANT/$VERSION/myProject-webapp-$VERSION.war indisponible" | tee -a $LOG_SCRIPTS
            exit 3
        fi
    else
        echo "Une erreur inconnue s'est produite lors du telechargement du livrable" | tee -a $LOG_SCRIPTS
        exit 4
    fi
}

###### fin de la verification de la dispo des ressources #####

############################################
#               fonction annexes           #
############################################

function traiter_retour()
{
    RET=$1
    echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
    if [ $RET -gt 0 ]
    then
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        MESSAGE_ERREUR="Une erreur s'est produite lors du deploiement de Pegase, consultez les logs." 
        echo "$MESSAGE_ERREUR" | tee -a $LOG_SCRIPTS
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        echo -e "Bonjour,\n\n"$MESSAGE_ERREUR"\nCdt" | mail -s "[ $ENVIRONNEMENT  ] Deploiement de Pegase $VERSION sur $HOSTNAME" $DESTINATAIRE_MAIL
        exit 25
    else
        echo "deploiement termine sans erreur sur $2" | tee -a $LOG_SCRIPTS
    fi
}

function preparation_machine()
{
    ping -c3 $1  > "/tmp/ping.txt"
    if [ $? -gt 0 ]
    then
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        echo "Une erreur s'est produite lors du ping de la machine  $1" | tee -a $LOG_SCRIPTS
        echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
        exit 30
    fi
}

function updateScriptBatch()
{
    echo "Mise a jour du script d'installation sur $1" | tee -a $LOG_SCRIPTS
    ssh root@$1 "cd /home/usrdev/myProject/; ./update_script_install_myProject_batch.sh"
}

function updateScriptWeb()
{
    echo "Mise a jour du script d'installation sur $1" | tee -a $LOG_SCRIPTS
    ssh root@$1 "cd /home/jboss/install/myProject/; ./update_script_install_myProject_webapp.sh"
}

function demarrer_installation()
{
    if [ "$MODE_INTERACTIF" = "1" ]; then
        saisie=""
        while [ -z "$saisie" -o "$saisie" != "o" -a "$saisie" != "n" ]; do
            echo "Commencer la livraison ? [o/n]"
            read saisie
        done
        
        if [ "$saisie" = "o" ]
        then
            echo "Demarrage de l'installation" | tee -a $LOG_SCRIPTS
        else
            echo "Arret de l'installation" | tee -a $LOG_SCRIPTS
            exit 42
        fi
    fi
}

function validation_etape()
{
    if [ "$MODE_INTERACTIF" = "1" ]; then
        echo "Merci de verifier si l'etape precedente s'est correctement terminee." | tee -a $LOG_SCRIPTS
        saisie=""
        while [ -z "$saisie" -o "$saisie" != "o" -a "$saisie" != "n" ]; do
            echo "Continuer la livraison ? [o/n]"
            read saisie
        done
        
        if [ "$saisie" = "o" ]
        then
            echo "Reprise de l'installation apres attente de 10 sec" | tee -a $LOG_SCRIPTS
            sleep 10
        else
            echo "Arret de l'installation" | tee -a $LOG_SCRIPTS
            exit 43
        fi
    fi
}

##################################################
#       param 1: machine cible
#       param 2: suffixe de la partition:
#         /usr/local/myProject pour les batchs
#         /usr/local/apps pour les jboss
#################################################
function verification_espace_disque()
{
    #recherche de l'espace disque dispo sur la partition cible
    FREE_SPACE=`ssh root@$1 df | grep /usr/local/$2 | awk '{print $3}'`
    #espace disque dispo necessaire:  > 70 000 o (~ 70 Mo)
    echo "FREE_SPACE $1 $2  $FREE_SPACE" | tee -a $LOG_SCRIPTS
    if [ -z $FREE_SPACE ] 
    then
        echo "Impossible de calculer l'espace disque disponible sur $1 dans la partition /usr/local/$2. Verifiez qu'elle existe." | tee -a $LOG_SCRIPTS
        exit 35  
    fi
        
    if [ $FREE_SPACE -lt 70000 ]
    then
        echo "il n'y a pas assez d'espace disque disponible sur la partition de la machine $1" | tee -a $LOG_SCRIPTS
        exit 40
    else
        echo "espace disque OK sur $1" | tee -a $LOG_SCRIPTS
    fi
}


###############################
#       preparation           #
###############################

echo "Preparation de l'installation, verification de la presence des machines" | tee -a $LOG_SCRIPTS

# Si on est en QUA_TMA ou en INT Alors l'installation doit se faire en mode standalone
if [ "$ENVIRONNEMENT" != "qua_tma" ] && [ "$ENVIRONNEMENT" != "int" ]
then
 if [ ! -z "$BATCH" ] 
    then
    preparation_machine $BATCH
    updateScriptBatch $BATCH

    demarrer_installation

    echo "$LIGNE_ETOILE" | tee -a $LOG_SCRIPTS
    echo "Installation sur $BATCH" | tee -a $LOG_SCRIPTS
    ssh root@$BATCH  "cd /home/usrdev/myProject;./$SCRIPT_BATCH $VERSION"
    traiter_retour $? $BATCH
    validation_etape
 fi

 demarrer_installation

for node in ${nodes[*]}; do
	LIST_SERVERS_TO_DEPLOY_ON+=$node"_"
done 
 
 preparation_machine $server
 updateScriptWeb $server
 verification_espace_disque $server "jboss"
 ssh root@$server "wall attention, installation de Pegase"

 ########### JBOSS ###########
 echo "Installation sur $server" | tee -a $LOG_SCRIPTS
 ssh root@$server "/home/jboss/install/myProject/install_myProject_webapp.sh $VERSION $APACHE $LIST_SERVERS_TO_DEPLOY_ON"    
 
 traiter_retour $? $server
 
 echo "Nettoyage des instances de chaque noeud jboss"
 for node in ${nodes[*]}; do
   printf "Nettoyage du noeud $node \n" | tee -a $LOG_SCRIPTS
   ssh root@$node "/home/jboss/myProject/cleanArtefacts.sh" $VERSION
 done

else
    echo "Installation en mode standalone"
	ssh root@$server "/home/jboss/install/myProject/install_myProject_webapp_int.sh $VERSION"
	
fi	
echo "fin de l'installation depuis $HOSTNAME" | tee -a $LOG_SCRIPTS	