#!/bin/bash

#################################################################
# PEGASE	 : Nettoyage des artefacts des instance 				#
# Parametre 1 Obligatoire : version (latest)                    #
#################################################################
if [ -z $1  ]
then
        echo "cleanArtefacts.sh --> Erreur : la version est obligatoire pour la configuration du module"
        exit 1;
fi
VERSION=$1
JBOSS_INSTANCE_DIR="/usr/local/jboss/domain/servers/"
function cleanDirectory(){
  if [ -d "$1" ]
  then
        CURRENT_MODULE=$1$VERSION
        for directory in `ls \$1 | grep -v \$VERSION`
        do
                CURRENT_DIR=$1$directory
                if [ -d "$CURRENT_DIR" ] && [ "$CURRENT_DIR" != "." ]
                then
                        if [ "$directory" != "$CURRENT_MODULE" ] &&  [ "$directory" != "main" ]
                        then
                                echo "Repertoire a supprimer : $directory"
                                rm -rf $CURRENT_DIR
                        fi
                fi
        done
  fi
}
echo "Nettoyage des anciennes instances JBoss ......"
cleanDirectory $JBOSS_INSTANCE_DIR                                                                 