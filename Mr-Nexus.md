# Nexus Repository Manager

Ce guide décrit l’installation locale de Nexus, les dépôts utilisés par Buy-02,
la publication et la récupération des artefacts, ainsi que les preuves à
présenter pour l’audit. Le pipeline complet est décrit dans
[`Mr-Jenkins.md`](./Mr-Jenkins.md).

## Architecture

Nexus est lancé par [`nexus/docker-compose.yml`](./nexus/docker-compose.yml).
Le volume `nexus_data` conserve la configuration, les utilisateurs et les
artefacts lorsque le conteneur est recréé.

| Adresse depuis l’hôte | Adresse depuis Jenkins | Usage |
|---|---|---|
| `http://localhost:8081` | `http://nexus:8081` | Interface et API Nexus |
| `localhost:8082` | `nexus:8082` | Push d’images vers `docker-hosted` |
| `localhost:8083` | `nexus:8083` | Proxy Docker Hub `docker-hub` |
| `localhost:8084` | `nexus:8084` | Pull via le groupe `docker-public` |

Les ports de l’hôte sont liés à `127.0.0.1` dans Compose. N’expose pas Nexus
sur un réseau public sans configurer TLS, les contrôles d’accès et les règles
réseau appropriés.

## Installation et premier accès

Le réseau Docker externe `jenkins` doit déjà exister. Depuis la racine du dépôt,
vérifie-le puis démarre Nexus :

```bash
docker network inspect jenkins
docker compose -f nexus/docker-compose.yml pull
docker compose -f nexus/docker-compose.yml up -d
docker compose -f nexus/docker-compose.yml ps
```

Le premier démarrage peut prendre quelques minutes. Suis les logs avec :

```bash
docker compose -f nexus/docker-compose.yml logs -f nexus
```

Ouvre `http://localhost:8081`. Le mot de passe administrateur initial peut être
lu une seule fois depuis le serveur ; ne partage pas cette sortie et ne la
commite pas :

```bash
docker compose -f nexus/docker-compose.yml exec nexus cat /nexus-data/admin.password
```

Connecte-toi comme `admin`, suis l’assistant de première connexion, choisis un
nouveau mot de passe et désactive l’accès anonyme si les dépôts doivent être
protégés. Stocke les mots de passe dans un gestionnaire de secrets.

Le conteneur Nexus doit fonctionner sous un utilisateur non-root. Vérifie-le
avec :

```bash
docker compose -f nexus/docker-compose.yml exec nexus id
```

L’UID affiché doit être différent de `0`.

## Dépôts Maven et Docker

Dans Nexus, ouvre **Administration → Repository → Repositories**. Vérifie les
dépôts existants avant d’en créer de nouveaux.

| Dépôt | Type | Configuration / usage |
|---|---|---|
| `maven-releases` | Maven hosted | Versions stables ; `Disable redeploy` |
| `maven-snapshots` | Maven hosted | Versions de développement `*-SNAPSHOT` ; autoriser les mises à jour |
| `maven-central` | Maven proxy | Remote storage : `https://repo.maven.apache.org/maven2/` |
| `maven-public` | Maven group | Membres : `maven-releases`, `maven-snapshots`, `maven-central` |
| `docker-hosted` | Docker hosted | Publication des images Buy-02 ; HTTP connector `8082` |
| `docker-hub` | Docker proxy | Proxy Docker Hub ; remote storage `https://registry-1.docker.io`, HTTP connector `8083` |
| `docker-public` | Docker group | Membres : `docker-hosted`, puis `docker-hub` ; HTTP connector `8084` |

La lecture et l’écriture sont séparées :

- Maven résout ses dépendances depuis `maven-public`, mais publie directement
  vers `maven-snapshots` ou `maven-releases`.
- Docker télécharge les images via `docker-public`, mais publie les images
  Buy-02 directement vers `docker-hosted`.

Le groupe `docker-public` doit inclure `docker-hosted` pour que les images
internes publiées puissent aussi être tirées par son URL.

## Maven : publier et récupérer un artefact

Le fichier [`settings.xml`](./settings.xml) configure `maven-public` comme
miroir Maven et utilise les identifiants fournis par l’environnement. Depuis
la racine du dépôt, saisis les identifiants sans inscrire le mot de passe dans
la commande :

```bash
export NEXUS_URL=http://localhost:8081
export NEXUS_CI_USER=UTILISATEUR_NEXUS
read -rsp 'Mot de passe Nexus: ' NEXUS_CI_PASSWORD
export NEXUS_CI_PASSWORD
echo
```

Pour publier `api-gateway` dans `maven-snapshots`, exécute depuis
`backend/api-gateway` :

```bash
./mvnw -B -s ../../settings.xml clean deploy
```

Le POM détermine le dépôt selon la version. Le pipeline publie les snapshots
depuis `main`. Pour une release, il faut créer et pousser un tag Git SemVer,
par exemple `v1.0.0` ; le pipeline retire le préfixe `v` et publie la version
stable correspondante dans `maven-releases`. Une version release déjà publiée
ne doit pas être réutilisée.

Pour récupérer l’artefact via Maven depuis la racine du dépôt (après sa
publication) :

```bash
./backend/api-gateway/mvnw -B -s settings.xml \
  org.apache.maven.plugins:maven-dependency-plugin:3.8.1:get \
  -Dartifact=com.example:api-gateway:0.0.1-SNAPSHOT
```

Remplace la version de l’exemple par celle qui est présente dans Nexus. Pour
vérifier le résultat, ouvre **Browse → maven-snapshots** ou
**Browse → maven-releases** et retrouve les coordonnées de l’artefact.

## Docker : publier et récupérer une image

Le pipeline construit les images et les publie dans `docker-hosted`. Les tags
de `main` contiennent le commit et le numéro de build
(`main-<sha>-<build>`). Les tags Git de release produisent des tags d’image
SemVer (par exemple `1.0.0`).

Exemple manuel depuis l’hôte, pour une image locale déjà construite :

```bash
docker login localhost:8082
docker tag backend-api-gateway:build-42 \
  localhost:8082/buy-02/backend-api-gateway:main-abc123-42
docker push localhost:8082/buy-02/backend-api-gateway:main-abc123-42
```

Pour récupérer la même image via `docker-public` :

```bash
docker login localhost:8084
docker pull localhost:8084/buy-02/backend-api-gateway:main-abc123-42
```

Remplace `build-42`, `abc123-42` et le nom de l’image par les valeurs réellement
publiées. Le compte doit pouvoir lire `docker-public` et publier sur
`docker-hosted`.

## Utilisateurs, rôles et permissions

Crée un compte Nexus dédié au pipeline, par exemple `jenkins-publisher`, plutôt
que d’utiliser `admin`. Attribue-lui uniquement les permissions nécessaires :

| Usage | Dépôt | Permissions |
|---|---|---|
| Résoudre les dépendances Maven | `maven-public` | Lecture |
| Publier des snapshots | `maven-snapshots` | `browse`, `read`, `add`, `edit` selon la configuration Nexus |
| Publier des releases | `maven-releases` | `browse`, `read`, `add`, `edit` selon la configuration Nexus |
| Télécharger des images | `docker-public` | Lecture |
| Publier des images | `docker-hosted` | `browse`, `read`, `add`, `edit` selon la configuration Nexus |

Dans Jenkins, le credential `nexus-credentials` doit utiliser le compte Nexus
de publication. Les permissions attribuées à ce compte doivent correspondre à
celles requises par le pipeline ; les droits de lecture sur un dépôt groupé ne
donnent pas le droit de publier sur un dépôt hosted.

Dans **Administration → Security → Realms**, vérifie que **Local
Authenticating Realm** et **Docker Bearer Token Realm** sont activés pour les
usages authentifiés correspondants.

## Captures pour l’audit

Les captures sont enregistrées dans [`nexus/screenshots/`](./nexus/screenshots/).
Masque les mots de passe, tokens et informations sensibles avant de les
partager.

| Preuve | Capture |
|---|---|
| Dashboard Nexus | [01-dashboard.png](./nexus/screenshots/01-dashboard.png) |
| Liste des dépôts | [02-repositories.png](./nexus/screenshots/02-repositories.png) |
| Artefacts Maven releases | [03-maven-releases.png](./nexus/screenshots/03-maven-releases.png) |
| Artefacts Maven snapshots | [04-maven-snapshots.png](./nexus/screenshots/04-maven-snapshots.png) |
| Configuration du proxy Maven Central | [05-maven-central-proxy.png](./nexus/screenshots/05-maven-central-proxy.png) |
| Membres du groupe Maven public | [06-maven-public-group.png](./nexus/screenshots/06-maven-public-group.png) |
| Plusieurs versions d’un artefact release | [07-release-versions.png](./nexus/screenshots/07-release-versions.png) |
| Images et tags Buy-02 dans Docker hosted | [08-docker-hosted.png](./nexus/screenshots/08-docker-hosted.png) |
| Configuration du proxy Docker Hub | [09-docker-hub-proxy.png](./nexus/screenshots/09-docker-hub-proxy.png) |
| Membres du groupe Docker public | [10-docker-public-group.png](./nexus/screenshots/10-docker-public-group.png) |
| Utilisateur Jenkins | [11-users.png](./nexus/screenshots/11-users.png) |
| Rôles Nexus | [12-roles.png](./nexus/screenshots/12-roles.png) |
| Privilèges par dépôt | [13-privileges.png](./nexus/screenshots/13-privileges.png) |
| Realms activés | [14-realms.png](./nexus/screenshots/14-realms.png) |

Complète ces captures par le log Jenkins d’un build réussi, qui montre les
étapes de publication, et par la sortie de `docker compose ... exec nexus id`
pour prouver l’exécution non-root. Assure-toi que les captures montrent bien la
configuration et les artefacts attendus.

## Arrêter Nexus

Depuis la racine du dépôt :

```bash
docker compose -f nexus/docker-compose.yml stop
docker compose -f nexus/docker-compose.yml start
docker compose -f nexus/docker-compose.yml down
```

Ces commandes conservent le volume `nexus_data`. N’utilise pas `down -v` sauf
si tu veux supprimer définitivement la configuration et les artefacts stockés
dans ce volume.
