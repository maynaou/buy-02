# Étape 1 — Installer Nexus Repository avec Docker

Cette étape démarre **Nexus Repository Manager OSS** dans un conteneur Docker.
Docker télécharge l’image officielle Sonatype, et un volume nommé conserve les
données Nexus séparément du conteneur. L’installation ne modifie pas les
configurations Docker Compose de l’application.

## Prérequis

- Docker installé et démarré
- Docker Compose v2 (`docker compose`, avec un espace)
- Environ **2 Go de mémoire disponibles** pour Nexus, en plus des autres
  applications éventuellement lancées sur la machine

Vérifiez les outils :

```bash
docker --version
docker compose version
docker info
```

La dernière commande doit réussir. Si elle indique que le daemon Docker n’est
pas joignable, démarrez Docker avant de continuer.

## 1. Démarrer Nexus

Depuis la racine du dépôt :

```bash
cd nexus
docker compose pull
docker compose up -d
```

- `pull` télécharge l’image `sonatype/nexus3`.
- `up -d` crée le conteneur et le démarre en arrière-plan.
- `restart: unless-stopped` permet à Docker de relancer Nexus après un
  redémarrage de la machine, sauf si vous l’avez arrêté explicitement.

Au premier démarrage, Nexus initialise son stockage. Cela peut prendre quelques
minutes. Suivez son démarrage avec :

```bash
docker compose logs -f nexus
```

Quand les journaux indiquent que Nexus est prêt, quittez le suivi avec
`Ctrl+C`. Cela arrête seulement l’affichage des journaux, pas le conteneur.

Vérifiez ensuite son état :

```bash
docker compose ps
```

Ouvrez [http://localhost:8081](http://localhost:8081) dans le navigateur.

## 2. Se connecter pour la première fois

L’image crée un mot de passe administrateur initial dans le volume Nexus.
Affichez-le dans le terminal :

```bash
docker compose exec nexus cat /nexus-data/admin.password
```

Dans l’interface web :

1. Cliquez sur **Sign in**.
2. Saisissez `admin` comme nom d’utilisateur et le mot de passe obtenu à
   l’étape précédente.
3. Suivez l’assistant pour définir un nouveau mot de passe administrateur.
4. Choisissez si l’accès anonyme doit être activé. Pour un dépôt interne, il est
   préférable de le désactiver et de créer des comptes/permissions adaptés
   avant d’ouvrir l’accès aux utilisateurs.

Conservez le nouveau mot de passe dans un gestionnaire de secrets. Ne le
commitez pas dans le dépôt et ne publiez pas la sortie de la commande de
récupération du mot de passe initial.

## Étape 2 — Créer les repositories

Cette étape configure des dépôts pour **Maven** et **Docker**. Dans Nexus,
chaque dépôt a un rôle différent :

- **Hosted** : stocke les artefacts internes que l’équipe publie.
- **Proxy** : met en cache les artefacts provenant d’un dépôt distant.
- **Group** : fournit une URL unique qui regroupe plusieurs dépôts.

### Pourquoi séparer les repositories ?

Un repository Nexus est un point de stockage et d’accès adapté à un format
(Maven ou Docker). On sépare les rôles pour éviter de mélanger les artefacts
que l’équipe publie avec ceux téléchargés depuis Internet, et pour pouvoir
contrôler les permissions et les règles de publication.

Le parcours Maven prévu est le suivant :

```text
Build Maven
   ├── télécharge ses dépendances depuis maven-public
   │      ├── maven-releases  (dépendances internes stables)
   │      ├── maven-snapshots (dépendances internes en développement)
   │      └── maven-central   (proxy vers Maven Central)
   └── publie son propre artefact dans maven-releases
       ou maven-snapshots, jamais dans le groupe
```

- **Pourquoi un proxy (`maven-central`) ?** Sans proxy, chaque build contacte
  directement Maven Central. Le proxy de Nexus récupère une dépendance externe
  lors de sa première demande puis la met en cache. Les builds suivants
  peuvent la récupérer depuis Nexus. Cela centralise les accès et améliore la
  disponibilité lorsque l’artefact demandé est déjà en cache.
- **Pourquoi un hosted pour les releases ?** Il stocke les versions stables
  produites par l’équipe. `Disable redeploy` empêche qu’une version publiée
  soit remplacée par un fichier différent : le même numéro de version garde
  ainsi le même contenu.
- **Pourquoi un hosted pour les snapshots ?** Une version telle que
  `1.2.0-SNAPSHOT` désigne un travail en cours et peut être publiée à nouveau.
  `Allow redeploy` autorise ces mises à jour. Une fois la version stabilisée,
  publie une version release, par exemple `1.2.0`.
- **Pourquoi un group (`maven-public`) ?** Maven n’a besoin que d’une URL de
  lecture. Nexus cherche la dépendance dans les membres du groupe et le build
  n’a pas à connaître chaque dépôt séparément. Le groupe sert à la résolution,
  pas au déploiement : on publie vers l’URL hosted correspondante.

Le parcours Docker suit le même principe, mais avec des images et le protocole
Docker Registry :

```text
docker pull depuis docker-public (port 8084)
   ├── image d’équipe déjà dans docker-hosted (port 8082)
   └── sinon, image publique récupérée via docker-hub (port 8083)

docker push publie directement dans docker-hosted (port 8082)
```

- **`docker-hosted`** contient les images construites par l’équipe. On y pousse
  les images ; on ne pousse pas dans un proxy ou un group.
- **`docker-hub`** fait office de cache pour les images publiques Docker Hub,
  au lieu que chaque poste contacte directement le registre externe.
- **`docker-public`** donne aux commandes Docker une adresse de lecture commune
  pour chercher une image interne ou une image mise en cache.
- **Pourquoi un port par dépôt Docker ?** Le client Docker parle au protocole de
  registre sur un port dédié. Nexus associe chaque port au bon dépôt ; le
  port `8081` reste celui de l’interface et de l’API Nexus.

Ces dépôts structurent les usages ; les créer ne publie pas automatiquement
les artefacts du projet. Il faudra ensuite configurer Maven et Docker pour
utiliser les bonnes URLs et fournir des credentials ayant les permissions
nécessaires.

Ouvrez `http://localhost:8081`, connectez-vous, puis allez dans
**Administration (icône engrenage) → Repository → Repositories**.

**Important : Nexus crée généralement les quatre dépôts Maven ci-dessous dès
son installation.** S’ils sont déjà présents dans la liste, ils sont déjà
configurés : ne les crée pas une deuxième fois. Vérifie leurs types et
paramètres. Seuls les dépôts absents doivent être créés. Les dépôts Docker,
eux, sont à créer manuellement pour ce projet.

### 2.1 Dépôts Maven

Vérifie que ces dépôts existent et ont les réglages ci-dessous. Pour en créer
un qui manque, clique sur **Create repository**, choisis le format/type indiqué,
configure-le, puis clique sur **Create repository**.

| Nom | Type | Paramètres principaux |
|---|---|---|
| `maven-releases` | `maven2 (hosted)` | Version policy : `Release` ; Deployment policy : `Disable redeploy` |
| `maven-snapshots` | `maven2 (hosted)` | Version policy : `Snapshot` ; Deployment policy : `Allow redeploy` |
| `maven-central` | `maven2 (proxy)` | Remote storage : `https://repo.maven.apache.org/maven2/` |
| `maven-public` | `maven2 (group)` | Membres, dans cet ordre : `maven-releases`, `maven-snapshots`, `maven-central` |

Pour `maven-releases`, `maven-snapshots` et `maven-central`, conserve le
format/layout Maven2 par défaut. Pour le groupe `maven-public`, vérifie que ses
membres comprennent ces trois dépôts ; s’il existe déjà, adapte ses membres au
besoin plutôt que de créer un second groupe portant le même nom. Les paramètres
d’accès peuvent conserver leurs valeurs par défaut pour ce développement local.

Après création, les URL de base sont :

```text
http://localhost:8081/repository/maven-releases/
http://localhost:8081/repository/maven-snapshots/
http://localhost:8081/repository/maven-central/
http://localhost:8081/repository/maven-public/
```

`maven-public` sert à **résoudre** les dépendances. Pour publier un artefact,
utilise directement le dépôt hosted correspondant à sa version.

Le pipeline Jenkins configure `maven-public` comme miroir Maven (`mirrorOf=*`)
pour les tests, les analyses Maven et les publications. Le compte
`nexus-credentials` doit avoir le droit `read` sur `maven-public`, ainsi que les
droits de publication sur les dépôts hosted concernés. Les commandes Maven du
pipeline passent ainsi par Nexus plutôt que de télécharger directement depuis
Maven Central.

### 2.2 Dépôts Docker

Le connecteur Docker utilise un port par dépôt. Le fichier
[`docker-compose.yml`](./docker-compose.yml) publie les ports `8082` à `8084`
uniquement sur la machine locale. Après avoir modifié Compose, appliquez les
ports depuis le dossier `nexus` :

```bash
docker compose up -d
docker compose ps
```

Dans **Create repository**, choisissez le format **docker** pour chaque dépôt :

| Nom | Type | Paramètres principaux |
|---|---|---|
| `docker-hosted` | `docker (hosted)` | HTTP connector : activé ; port : `8082` |
| `docker-hub` | `docker (proxy)` | Remote storage : `https://registry-1.docker.io` ; HTTP connector : activé ; port : `8083` |
| `docker-public` | `docker (group)` | HTTP connector : activé ; port : `8084` ; membre : `docker-hosted`, puis `docker-hub` |

Si l’écran de configuration du proxy propose **Docker Index**, choisis
**Use Docker Hub**. Ne configure pas de compte Docker Hub pour le cache public
de base. Laisse les autres paramètres à leur valeur par défaut pour cette
installation locale.

Pour le pipeline, accorde également à `nexus-credentials` le droit `read` sur
`docker-public`. Les Dockerfiles et Compose utilisent le connecteur du groupe
`nexus:8084` pour les images de base et les images publiques Kafka/MongoDB.
Jenkins s’authentifie à ce groupe avant les builds et les tests ; Nexus met les
images en cache lors du premier téléchargement. Le daemon Docker-in-Docker est
configuré pour accepter ce connecteur HTTP.

Adresses des dépôts Docker :

```text
docker-hosted : localhost:8082   # publication d'images
docker-hub     : localhost:8083   # proxy Docker Hub direct
docker-public  : localhost:8084   # URL groupée pour les téléchargements
```

Si Docker ne parvient pas à s’authentifier aux dépôts, vérifie dans
**Administration → Security → Realms** que **Docker Bearer Token Realm** est
activé, puis enregistre la configuration. Les clients Docker locaux utilisent
un connecteur HTTP ; garde ces ports liés à `127.0.0.1` et ne les expose pas au
réseau sans configurer HTTPS et les contrôles d’accès adaptés.

### 2.3 Vérifier les dépôts

Dans l’écran **Repositories**, vérifie d’abord les quatre dépôts Maven (qui sont
normalement fournis par défaut), puis les trois dépôts Docker que tu as créés.
La commande suivante envoie une requête HTTP `GET` à l’URL du dépôt groupé
Maven :

```bash
curl -sS -o /dev/null -w 'Maven group: HTTP %{http_code}\n' \
  http://localhost:8081/repository/maven-public/
```

Voici le rôle de chaque option :

- `curl` envoie la requête HTTP au serveur Nexus.
- `-sS` masque la barre de progression, mais affiche les erreurs réseau.
- `-o /dev/null` jette le contenu de la réponse ; il reste seulement le code
  HTTP affiché par la commande.
- `-w '... %{http_code}\n'` affiche le code HTTP reçu, par exemple `200` ou
  `401`.
- `\` à la fin de la ligne indique au shell que la commande continue sur la
  ligne suivante.

L’URL `/repository/maven-public/` vise le dépôt **group** Maven. C’est le point
d’entrée que Maven utilisera plus tard pour chercher des dépendances dans ses
différents membres (releases, snapshots et proxy Maven Central).

### Comprendre la réponse `401`

Si la commande affiche `HTTP 401`, cela signifie que Nexus a bien répondu, mais
qu’il refuse cette requête **sans authentification**. Dans cette commande,
aucun nom d’utilisateur ni mot de passe n’est envoyé. C’est normal si l’accès
anonyme est désactivé ou si l’utilisateur anonyme n’a pas la permission de lire
ce dépôt. Ce code ne signifie donc pas à lui seul que le dépôt est absent ou mal
configuré. Dans le navigateur, une session déjà connectée peut masquer cette
différence.

Pour refaire le test en t’authentifiant, utilise un utilisateur Nexus ayant la
permission de lire le dépôt. `curl` te demandera le mot de passe sans l’écrire
dans la commande ni l’enregistrer directement dans l’historique du shell :

```bash
curl -u admin -sS -o /dev/null -w 'Maven group authentifié: HTTP %{http_code}\n' \
  http://localhost:8081/repository/maven-public/
```

Un code `200` indique que la requête est autorisée. Un `401` même après
authentification peut signifier que le mot de passe est incorrect ou que ce
compte n’a pas accès au dépôt. Pour un usage d’équipe, préfère un compte dédié
avec uniquement les permissions nécessaires plutôt que le compte `admin`.

Le test ci-dessus vérifie surtout l’accès HTTP au dépôt groupé. Pour vérifier
qu’une dépendance Maven précise peut être lue via ce groupe, teste un fichier
de métadonnées connu :

```bash
curl -u admin -sS -o /dev/null -w 'Maven metadata: HTTP %{http_code}\n' \
  http://localhost:8081/repository/maven-public/org/apache/maven/maven-artifact/maven-metadata.xml
```

Sur une instance en ligne et avec les permissions nécessaires, `200` indique
que les métadonnées sont accessibles. Ce test provoque une requête au groupe ;
si l’artefact vient de `maven-central`, Nexus peut alors le télécharger dans
son dépôt proxy et le mettre en cache.

Tu peux aussi vérifier que les points d’accès des dépôts Docker répondent :

```bash
curl -sS -o /dev/null -w 'Docker hosted: HTTP %{http_code}\n' \
  http://localhost:8082/v2/
curl -sS -o /dev/null -w 'Docker proxy: HTTP %{http_code}\n' \
  http://localhost:8083/v2/
curl -sS -o /dev/null -w 'Docker group: HTTP %{http_code}\n' \
  http://localhost:8084/v2/
```

Pour ces URL Docker `/v2/`, `401` est aussi souvent normal : le protocole de
registre Docker demande une authentification par jeton. L’important est de
recevoir une réponse HTTP de Nexus. Une erreur de connexion (`000` dans la
sortie curl) indique plutôt que Nexus n’écoute pas sur le port attendu, que le
connecteur correspondant n’est pas activé ou que le conteneur doit finir son
démarrage.

Dans Nexus, ouvre aussi chacun des dépôts Maven et utilise **Verify** sur son
URL distante si le bouton est disponible. Un dépôt proxy doit être en ligne
pour récupérer et mettre en cache les dépendances externes.

## Étape 3 — Créer le JAR et le publier sur Nexus

Les services backend de ce projet sont des applications Spring Boot empaquetées
en JAR (aucun service ne configure le packaging WAR). Le pipeline construit et
teste les JAR avec Maven via `maven-public`, puis copie ces mêmes JAR dans les
images runtime Java ; les images ne reconstruisent pas les services en
contournant le cache Maven. Pour un build local, `bash ./scripts/package-backend.sh`
construit les JAR avant `docker compose up --build`. Leurs versions actuelles
finissent par `-SNAPSHOT` : publie-les donc dans `maven-snapshots`.

Le fichier [`settings.xml`](../settings.xml) du projet configure le miroir Maven
et lit l’URL et les identifiants depuis l’environnement : aucun secret n’est
stocké dans Git. Avant d’utiliser Maven localement, définis :

```bash
export NEXUS_URL=http://localhost:8081
export NEXUS_CI_USER=UTILISATEUR_NEXUS
export NEXUS_CI_PASSWORD
read -rsp 'Mot de passe Nexus: ' NEXUS_CI_PASSWORD
echo
```

Le miroir fait passer la résolution par `maven-public`. Les IDs des serveurs
`nexus-releases` et `nexus-snapshots` doivent correspondre aux IDs de
`distributionManagement` des POMs. Jenkins fournit ces mêmes variables au
fichier `settings.xml` avec l’URL interne `http://nexus:8081`.

Par exemple, pour construire et publier `api-gateway`, exécute depuis
`backend/api-gateway` :

```bash
./mvnw -B -s ../../settings.xml clean deploy
```

Maven exécute les tests, crée le JAR dans `target/`, puis choisit automatiquement
`maven-snapshots` pour une version `-SNAPSHOT` ou `maven-releases` pour une
version stable. Les POMs de chacun des sept services contiennent ces URL dans
`distributionManagement`. Pour construire les JARs localement en passant par
le miroir Nexus, exécute depuis la racine du dépôt :

```bash
bash ./scripts/package-backend.sh
```

Vérifie ensuite dans l’interface Nexus que l’artefact apparaît sous
**Browse → maven-snapshots**.

Dans le pipeline Jenkins, cette publication est automatisée par l’étape
**Publish Backend Artifacts to Nexus**, exécutée uniquement sur `main` après
les tests et les Quality Gates. Elle publie les sept services en utilisant le
credential Jenkins `nexus-credentials` et l’adresse réseau interne
`http://nexus:8081`.

Pour publier une version stable, pousse un tag Git au format `vMAJOR.MINOR.PATCH`
(par exemple `v1.0.0`). Jenkins retire le `v` pour définir la version Maven et
publie dans `maven-releases`. Le compte de publication doit aussi posséder les
privilèges `browse`, `read`, `add` et `edit` sur ce dépôt. Les versions releases
étant immuables, un tag déjà publié ne peut pas être redéployé.

## Configuration Docker Compose

Le fichier [`docker-compose.yml`](./docker-compose.yml) configure les éléments
suivants :

| Paramètre | Rôle |
|---|---|
| `sonatype/nexus3:latest` | Image officielle Nexus Repository Manager OSS |
| `127.0.0.1:8081:8081` | Publie l’interface sur le port 8081, accessible seulement depuis cette machine |
| `127.0.0.1:8082-8084` | Ports locaux des connecteurs des dépôts Docker |
| `nexus_data:/nexus-data` | Stocke durablement la configuration, les comptes et les artefacts |
| `unless-stopped` | Redémarre le service automatiquement, sauf arrêt manuel |

Le conteneur officiel démarre Nexus sous un utilisateur non-root. Vous pouvez
le vérifier après le démarrage :

```bash
docker compose exec nexus id
```

La sortie doit indiquer un UID différent de `0`. Cela concerne l’utilisateur
qui exécute Nexus **dans le conteneur** ; Docker lui-même peut nécessiter des
privilèges administrateur pour gérer les conteneurs sur l’hôte.

L’application du dépôt utilise Java 17, tandis que le cahier des charges Maven
peut demander Java 11 pour les builds. Le runtime de Nexus est fourni avec
l’image Nexus et est indépendant du JDK utilisé pour compiler les services.

## 4. Arrêter, redémarrer et préserver les données

Depuis le dossier `nexus` :

```bash
docker compose stop
docker compose start
docker compose down
```

`stop`, `start` et `down` conservent le volume `nexus_data`. **Ne lancez pas**
`docker compose down -v` sauf si vous voulez supprimer définitivement la base
Nexus et tous les artefacts qui y sont stockés.

## Sécurité et portée de cette installation

Le port est lié à `127.0.0.1` : Nexus est destiné ici à un usage local de
développement et n’est pas publié sur le réseau. Ne remplacez pas cette adresse
par `0.0.0.0` sur un serveur accessible sans avoir d’abord configuré TLS,
l’authentification, les rôles et les règles réseau. Pour une installation
d’équipe ou de production, utilisez une version d’image explicitement figée,
prévoyez des sauvegardes du volume et suivez les recommandations Sonatype.

## Étape suivante

Les JAR backend peuvent maintenant être publiés dans les dépôts hosted Maven
de Nexus. Les dépôts Docker peuvent être utilisés séparément pour les images
du projet.
