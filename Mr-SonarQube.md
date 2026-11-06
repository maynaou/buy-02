# SonarQube — Analyse de qualité du code

SonarQube analyse les sept composants backend et le frontend dans le pipeline
[`Jenkinsfile`](./Jenkinsfile). Il reçoit les rapports de couverture produits
par les tests, analyse le code, puis communique le résultat du Quality Gate à
Jenkins.

## Architecture

```text
Tests backend ── Surefire / JaCoCo ──┐
                                     ├──> SonarQube ── Quality Gate ──> Jenkins
Tests frontend ── JUnit / LCOV ─────┘
```

Le serveur SonarQube est le service `sonarqube` de
[`jenkins-setup/docker-compose.yml`](./jenkins-setup/docker-compose.yml).
Il est disponible dans le réseau Jenkins sur `http://sonarqube:9000` et depuis
l’hôte sur `http://localhost:9000`. Jenkins utilise une installation Sonar
nommée `SonarQube` et le credential `sonar-token`, configurés dans
[`jenkins-casc.yaml`](./jenkins-setup/jenkins/jenkins-casc.yaml).

## Projets analysés

Chaque composant possède une clé de projet distincte :

| Composant | Clé SonarQube |
|---|---|
| `api-gateway` | `buy-02-api-gateway` |
| `discovery-service` | `buy-02-discovery-service` |
| `security-service` | `buy-02-security-service` |
| `user-service` | `buy-02-user-service` |
| `product-service` | `buy-02-product-service` |
| `media-service` | `buy-02-media-service` |
| `order-service` | `buy-02-order-service` |
| Frontend | `buy-02-frontend` |

## Backend — Maven, Surefire et JaCoCo

Jenkins exécute d’abord les tests de chaque service en parallèle :

```bash
./mvnw clean test
```

Les rapports produits sont :

| Rapport | Chemin | Utilisé par |
|---|---|---|
| Tests JUnit | `target/surefire-reports/*.xml` | Jenkins |
| Couverture JaCoCo | `target/site/jacoco/jacoco.xml` | SonarQube |

Les POM incluent le plugin JaCoCo. Jenkins lance ensuite le scanner Maven pour
chaque projet et fournit le chemin du rapport XML avec
`sonar.coverage.jacoco.xmlReportPaths`.

Pour lancer localement les tests d’un service :

```bash
cd backend/product-service
./mvnw clean test
```

## Frontend — Angular, Karma et LCOV

Dans le pipeline, les tests Angular sont lancés ainsi :

```bash
npm ci
npm test -- --watch=false --include='src/**/*.spec.ts'
```

La configuration Angular active la couverture et Karma génère :

- `frontend/test-results/karma-results.xml` pour les résultats JUnit ;
- `frontend/coverage/lcov.info` pour la couverture utilisée par SonarQube.

L’analyse frontend utilise `npx sonar-scanner`, analyse `src`, exclut les tests
`*.spec.ts`, `node_modules` et `dist`, puis transmet le rapport LCOV.

## Quality Gate

Après chaque analyse, Jenkins attend le résultat SonarQube avec
`waitForQualityGate abortPipeline: true` et un délai d’attente de cinq minutes.
Si le Quality Gate échoue ou n’est pas reçu dans le délai, le pipeline s’arrête
avant le build Docker et les étapes de déploiement.

Les conditions du Quality Gate sont définies côté SonarQube ; elles ne sont pas
fixées par les commandes du scanner dans le dépôt. Le Quality Profile définit
les règles d’analyse et le Quality Gate décide si les résultats satisfont les
conditions configurées.

## Ordre dans le pipeline

```text
Tests backend en parallèle
        ↓
Analyses backend et Quality Gates
        ↓
Tests frontend + couverture LCOV
        ↓
Analyse frontend + Quality Gate
        ↓
Build Docker
        ↓
Tests E2E
        ↓
Déploiement sur main
```

Les analyses backend et leurs Quality Gates sont exécutées l’une après l’autre
par le Jenkinsfile afin d’éviter de surcharger SonarQube et de garder chaque
résultat associé à son analyse. Les étapes de build Docker, E2E et déploiement
ne sont atteintes que si les tests et Quality Gates précédents réussissent.

## Diagnostic

- Dans Jenkins, vérifiez les logs des étapes **Backend SonarQube Analysis** et
  **Frontend SonarQube Analysis**.
- Vérifiez que le serveur Jenkins est configuré sous le nom exact `SonarQube`.
- Vérifiez la disponibilité de `http://sonarqube:9000` depuis le réseau Jenkins.
- Vérifiez que le credential `sonar-token` est valide.
- Vérifiez l’existence du rapport correspondant avant l’analyse :
  `target/site/jacoco/jacoco.xml` ou `frontend/coverage/lcov.info`.

> Surefire/Karma exécutent les tests, JaCoCo/LCOV mesurent la couverture, le
> scanner transmet les résultats et SonarQube calcule le Quality Gate. Ces rôles
> sont complémentaires.
