# Jenkins — Pipeline CI/CD

Ce document décrit le pipeline réellement défini dans [`Jenkinsfile`](./Jenkinsfile)
et son infrastructure Docker Compose située dans [`jenkins-setup/`](./jenkins-setup/).

## Architecture

```mermaid
flowchart LR
    github[GitHub]
    jenkins[Jenkins<br/>jenkins-blueocean]
    dind[Docker Engine distant<br/>jenkins-docker / DinD]
    sonar[SonarQube]
    app[Buy-02<br/>services backend + frontend]

    github -->|Multibranch scan| jenkins
    jenkins -->|Docker CLI via TLS :2376| dind
    jenkins -->|Analyse de code| sonar
    dind -->|Build, tests E2E, déploiement| app
```

Jenkins et le moteur Docker sont deux conteneurs distincts :

| Conteneur | Rôle |
|---|---|
| `jenkins-blueocean` | Jenkins, Docker CLI, Java 21, Node.js, Chromium et plugins |
| `jenkins-docker` | Daemon Docker-in-Docker qui construit et exécute les conteneurs Buy-02 |
| `sonarqube` | Serveur d’analyse de code, accessible à Jenkins sur `http://sonarqube:9000` |

Le CLI Docker communique avec DinD par TLS sur `docker:2376`. Les variables
`DOCKER_HOST`, `DOCKER_CERT_PATH` et `DOCKER_TLS_VERIFY` sont configurées dans
[`jenkins-setup/docker-compose.yml`](./jenkins-setup/docker-compose.yml).

## Démarrer l’infrastructure Jenkins

Le fichier Compose attend les valeurs de configuration et credentials déclarés
dans [`jenkins-casc.yaml`](./jenkins-setup/jenkins/jenkins-casc.yaml). Configurez
ces valeurs dans l’environnement de lancement ou dans un fichier `.env` local
non versionné. Ne commitez ni secrets ni clés.

Depuis la racine du dépôt :

```bash
docker compose -f jenkins-setup/docker-compose.yml up --build -d
```

Accès locaux :

| Service | URL |
|---|---|
| Jenkins | `http://localhost:8080` |
| SonarQube | `http://localhost:9000` |

Jenkins est configuré en multibranch : la découverte GitHub est périodiquement
relancée et le dépôt configure la découverte des branches et des Pull Requests.
La configuration présente ne crée pas elle-même de tunnel Ngrok.

## Étapes du pipeline

Le pipeline utilise `IMAGE_TAG=build-${BUILD_NUMBER}`, désactive les exécutions
concurrentes, conserve les stashes récents et applique un timeout global de
30 minutes.

1. **Checkout** — récupère la révision sélectionnée par le job multibranch.
2. **Prepare Secrets** — écrit les clés JWT, les certificats TLS et la
   configuration Cloudinary à partir des credentials Jenkins via
   [`scripts/prepare-secrets.sh`](./scripts/prepare-secrets.sh).
3. **Backend Unit & Integration Tests** — lance `./mvnw clean test` en parallèle
   pour les sept services backend.
4. **Backend SonarQube Analysis** — analyse les sept services et attend leur
   Quality Gate.
5. **Frontend Unit & Integration Tests** — exécute `npm ci`, puis les tests
   Angular avec la couverture activée.
6. **Frontend SonarQube Analysis** — analyse le frontend et attend son Quality
   Gate.
7. **Publish Backend Artifacts to Nexus** — sur `main`, publie les JARs des
   sept services backend dans `maven-snapshots`. Sur un tag de release
   `vMAJOR.MINOR.PATCH`, publie les mêmes services dans `maven-releases` avec
   une version Maven sans le préfixe `v`. Le credential Jenkins
   `nexus-credentials` fournit l’authentification ; Nexus est joint sur
   `http://nexus:8081`.
8. **Docker Build** — construit les images backend et frontend, puis conserve
   le tag de build pour les étapes suivantes.
9. **End-to-End Tests** — exécute [`scripts/e2e-tests.sh`](./scripts/e2e-tests.sh)
   avec les conteneurs construits. Le script attend que le Gateway réponde, lance
   Playwright et supprime les données créées par le test, y compris si le test
   échoue.
10. **Publish Docker Images to Nexus** — après les tests E2E réussis, publie
   les huit images applicatives dans `docker-hosted` sur `main` et sur les tags
   de release. Les images `main` sont taguées avec le commit et le numéro de
   build (`main-<sha>-<build>`),
   celles d'une release avec sa version (`1.0.0`). Le daemon Docker-in-Docker
   est configuré pour joindre le connecteur HTTP interne `nexus:8082`. Le
   credential `nexus-credentials` doit avoir les privilèges `browse`, `read`,
   `add` et `edit` sur `docker-hosted`. Après modification du Compose, appliquez
   la configuration en recréant le daemon :

   ```bash
   docker compose -f jenkins-setup/docker-compose.yml up -d --force-recreate jenkins-docker
   ```

11. **Deploy Backend**, **Deploy Frontend**, **cleanUp** — exécutés uniquement
   sur la branche `main`. Les étapes de déploiement utilisent les scripts de
   déploiement et de rollback du dossier `scripts/`.

Si une étape échoue, Jenkins arrête les étapes suivantes. Les rapports JUnit
disponibles sont publiés à la fin du build et le pipeline envoie un courriel de
succès ou d’échec.

Pour publier une release, créez un tag SemVer sur le commit validé de `main`,
puis poussez ce tag :

```bash
git tag v1.0.0
git push origin v1.0.0
```

Jenkins découvre les tags GitHub. Le pipeline valide le format
`vMAJOR.MINOR.PATCH`, remplace temporairement la version Maven des POMs dans
son workspace, puis publie les releases dans `maven-releases`. Les POMs du
dépôt Git ne sont pas modifiés. Configurez pour `nexus-credentials` les droits
`browse`, `read`, `add` et `edit` sur `maven-releases` ; le dépôt release doit
refuser le redéploiement d’une version déjà publiée. Après les tests E2E, les
images Docker de cette release sont également publiées dans `docker-hosted`
avec le même numéro de version.

## Tests E2E dans DinD

Le script E2E démarre d’abord la stack backend, puis le frontend avec le même
`IMAGE_TAG`. Le test utilise les adresses locales HTTPS :

- Frontend : `https://localhost:4200`
- API Gateway : `https://localhost:8888`

Ces ports sont publiés par les Compose applicatifs sur le conteneur DinD. Le
script récupère l’adresse DNS `docker` et la transmet comme
`E2E_DOCKER_HOST_IP`. Playwright configure Chromium pour résoudre `localhost`
vers cette adresse, afin de conserver les URL HTTPS configurées dans
l’application.

Le pipeline n’utilise plus de script TCP proxy. Une erreur
`ERR_CONNECTION_REFUSED` doit donc être diagnostiquée en vérifiant le healthcheck
du frontend et la publication des ports `4200` et `8888` par DinD.

## Credentials Jenkins

La configuration JCasC déclare les credentials nécessaires au pipeline :

- GitHub et SMTP
- Credentials administrateur Jenkins
- MongoDB et mot de passe TLS
- URL Cloudinary
- Clés JWT privée et publique
- Certificat et clé TLS du frontend
- Token SonarQube

Le token SonarQube est référencé par l’installation Jenkins nommée `SonarQube`.
Ne stockez pas les valeurs réelles dans les fichiers suivis par Git.

## Journaux et commandes de diagnostic

```bash
docker compose -f jenkins-setup/docker-compose.yml ps
docker compose -f jenkins-setup/docker-compose.yml logs -f jenkins-blueocean
docker compose -f jenkins-setup/docker-compose.yml logs -f sonarqube
docker exec jenkins-docker docker ps
docker exec jenkins-docker docker info
```

Arrêt de l’infrastructure sans supprimer les données persistantes :

```bash
docker compose -f jenkins-setup/docker-compose.yml down
```

La suppression des volumes détruit les données Jenkins, SonarQube et les
certificats DinD ; ne la faites que si cette perte de données est voulue.
