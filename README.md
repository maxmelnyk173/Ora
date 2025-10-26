# Ora – Learning Platform (Microservices Sandbox Project)

> ⚠️ **Disclaimer: This is a learning project.**
> It is used to explore and experiment with different technologies and architectural patterns. The project is in **early development**, and many components are incomplete or experimental. Expect bugs, inconsistent behavior, and rough edges. Contributions and suggestions are always welcome!

### 🚀 Project Overview

Ora is a learning platform where educators can create and sell content, and users can purchase and consume it.

**Key Features:**
* 🎥 **Pre-recorded Courses:** Instant access after purchase.
* 👥 **Group & Private Sessions:** Live, scheduled sessions for groups or individuals.
* 🌐 **Online Courses:** Live, multi-session courses with a predefined schedule.
* 💬 **Chat:** Private and group messaging between users and educators (planned).
* 📅 **Scheduling Tools:** Calendars for educators to define availability and manage events.

Users can browse and purchase content, and also apply to become educators to sell their own.

### 🧱 Architecture

This platform uses a **polyglot microservices architecture**. Each service is a self-contained application with a distinct responsibility, communicating via a mix of synchronous and asynchronous patterns.

- **API Gateway:** An **NGINX** reverse proxy is the single entry point for all external traffic, routing requests to the appropriate backend service.
- **Communication:** Services use **REST APIs** for direct requests and **RabbitMQ** for event-driven, asynchronous communication.
- **Authentication:** **Keycloak** is the central identity and authorization provider, securing all services.

### 📂 Folder Structure

```bash
.
├── backend/                # Microservices
│   ├── auth/               # Java + Spring Boot
│   ├── profile/            # Java + Spring Boot + JPA
│   ├── learning/           # ASP.NET 9 + EF Core
│   ├── scheduling/         # Go + Chi + SQLX
│   ├── payment/            # Python + FastAPI
│   └── chat/               # (Planned) NestJS
├── frontend/               # Web client (React + Vite + TS + Tailwind)
│   └── web/                # Main web app
├── infra/                  # Infrastructure configuration for Docker & Kubernetes
│   ├── docker/             # Docker Compose setup for local development
│   │   ├── docker-compose.yml
│   │   ├── configs/        # Keycloak realm & observability configs
│   │   └── scripts/        # Helper scripts (e.g., init-db.sh)
│   └── minikube/           # Kubernetes setup using Minikube and Helm
│       ├── platform/       # Platform-level Helm chart (Postgres, Keycloak, etc.)
│       ├── common/         # Common Helm chart inherited by services
│       └── scripts/        # Scripts to initialize a k8s cluster
├── certs/                  # TLS certificates and root CA (mkcert generated)
```

### 🛠️ Technologies

Each microservice is built with a technology stack chosen for its specific domain.

| Service        | Language     | Key Frameworks & Libraries         |
| -------------- | ------------ | ---------------------------------- |
| **Auth**       | Java 21      | Spring Boot, Keycloak Admin Client |
| **Profile**    | Java 21      | Spring Boot, JPA, AMQP             |
| **Learning**   | .NET 9       | ASP.NET, Entity Framework Core     |
| **Scheduling** | Go 1.24+     | Chi, SQLX, AMQP                    |
| **Payment**    | Python 3.11+ | FastAPI, SQLAlchemy, aio-pika      |
| **Chat**       | *(planned)*  | NestJS                             |
| **Web**        | TypeScript   | React, Vite, Tailwind CSS          |

### 🏗️ Local Environment Setup

The platform is container-native and can be run locally using Docker Compose or deployed to Kubernetes (Minikube).

#### Prerequisites: HTTPS & TLS

**This is a critical first step.** The entire platform requires locally trusted TLS certificates to function.

1.  **Install `mkcert`:** Follow the instructions at [mkcert.dev](https://mkcert.dev/) to install it.
2.  **Generate Certificates:** Run `mkcert` to generate a certificate for `*.127.0.0.1.nip.io` and `127.0.0.1.nip.io`. These domains are hardcoded and resolve to your local machine.
3.  **Place Certificates:** Move the generated certificate (`cert.pem`) and key (`cert-key.pem`) files into the `certs/` directory at the project root. You must also include the root CA file (`rootCA.pem`) in this directory so the service containers can trust the certificates.

#### 1. Running with Docker Compose

The simplest way to run the entire stack for local development.
- **Configuration:** Defined in `infra/docker/docker-compose.yml`.
- **Orchestration:** Spins up all microservices, the frontend, and infrastructure (PostgreSQL, RabbitMQ, Keycloak, etc.).
- **Networking:** All services are connected to a shared `ora-net` bridge network.
- **Gateway:** The **NGINX** container serves as the reverse proxy and terminates HTTPS traffic.
- **Scripts (`/infra/docker/scripts`):**
  - `init-db.sh`: Initializes PostgreSQL databases on first startup.
  - `run.ps1`: A PowerShell wrapper for `docker-compose` commands to simplify starting/stopping the environment.

#### 2. Deploying to Kubernetes (Minikube & Helm)

The project is also configured for deployment to a local Kubernetes cluster.
- **Helm Charts:** **Helm** is used to package and manage the applications.
  - `infra/minikube/platform`: Deploys shared infrastructure (PostgreSQL, Keycloak).
  - `infra/minikube/common`: A common chart template inherited by each microservice.
  - `backend/<service>/k8s`: Each microservice contains its own Helm chart.
- **Scripts (`/infra/minikube/scripts`):**
  - A collection of PowerShell scripts to automate deploying the entire stack to Minikube.

### 🔍 Monitoring & Observability

A robust observability stack is a core component of the platform, providing deep insights into application performance and behavior. It is pre-configured for both local and Kubernetes environments.

- **OpenTelemetry:** The backbone for generating and collecting telemetry data (traces, metrics, logs) across all services.
- **Prometheus:** For collecting and storing time-series metrics.
- **Loki:** For log aggregation and querying.
- **Tempo:** For distributed trace storage.
- **Grafana:** For visualizing all telemetry data with pre-configured dashboards.

Configurations can be found in `infra/docker/configs` for Docker Compose and within the Helm charts in the `infra/minikube` directory for Kubernetes.

### 🔐 Authentication & Authorization

**Keycloak** is the central authentication provider for the entire platform.

- The **Auth service** (Java/Spring Boot) acts as a facade, providing domain-specific logic on top of Keycloak's APIs.
- The Keycloak realm, clients, and roles are configured to be automatically imported on startup in both environments:
  - For **Docker Compose**, the configuration is defined in `infra/docker/configs/realm-config.json`.
  - For **Kubernetes**, the setup is managed via the Keycloak Helm chart and its corresponding `values.yaml` file.