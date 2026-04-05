# Fix Trading Simulator

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Project Structure](#project-structure)
- [Features](#features)
- [Running the project](#running-the-project)
- [Images](#images)
- [Help Queries](#help-queries)

# Overview

A trading simulator between a Broker and a Stock Exchange using the [Financial Information eXchange (FIX) Protocol](https://www.fixtrading.org/). It's a study project using [QuickFIX/J](https://www.quickfixj.org/), [Quarkus](https://quarkus.io/), [Angular](https://angular.io/), Docker, Docker Compose and [PostgreSQL](https://www.postgresql.org/).

If you want to participate on this project, just open an issue and we can talk about!

Both Broker and Exchange systems were built with Quarkus on the back-end and Angular on the front-end. 

The back-ends communicate each other with QuickFIX/J and each has a schema into the PostgreSQL.

Each Angular front-end communicates with the Quarkus back-end using REST and Websockets.

# System Architecture

The architecture consists of:
- **Exchange Back-End**: Quarkus REST API with QuickFIX Acceptor
- **Exchange Front-End**: Angular UI for exchange management
- **Broker Back-End**: Quarkus REST API with QuickFIX Initiator
- **Broker Front-End**: Angular UI for broker trading platform
- **PostgreSQL**: Shared database for logging and persistence

# Project Structure

```
fix-trading-simulator/
├── scripts/
│   ├── build/
│   ├── debug/
│   ├── ops/
│   ├── tests/
│   └── validation/
├── exchange-back-end/
├── exchange-front-end/
├── broker-back-end/
├── broker-front-end/
├── docker-compose.yml
└── README.md
```

[Broker back-end](./broker-back-end/README.md)

[Broker front-end](./broker-front-end/README.md)

[Exchange back-end](./exchange-back-end/README.md)

[Exchange front-end](./exchange-front-end/README.md)

# Features

## Orders

You can submit, negotiate, cancel and list your orders.

It's possible to set the Exchange to automatically negotiate the orders.

Every change in the orders are broadcasted using websockets and are immediately updated on the front-end.

## Session

Make logon and logout.

View the session status and storage.

View the session configuration.

List the messages sent from the session.

## Logs

List the FIX events.

List the messages received and sent.

# Running the project

## With docker-compose

After start, access project at:
- Broker Front end
  - http://localhost/
- Broker Back end swagger: 
  - http://localhost:8080/q/swagger-ui/
- Exchange Front end
  - http://localhost:90/
- Exchange Back end swagger: 
  - http://localhost:8090/q/swagger-ui/
- PostgreSQL:
  - jdbc:postgresql://localhost:5432/postgres
  - user: postgres
  - password: postgres

### Using the Docker Hub Images

Inside the root folder of the project, execute:
```
$ chmod +x ./scripts/build/run-from-docker-hub.sh
$ ./scripts/build/run-from-docker-hub.sh
```

Docker Hub images:
- [exchange-back-end](https://hub.docker.com/repository/docker/felipewind/exchange-back-end)
- [exchange-front-end](https://hub.docker.com/repository/docker/felipewind/exchange-front-end)
- [broker-back-end](https://hub.docker.com/repository/docker/felipewind/broker-back-end)
- [broker-front-end](https://hub.docker.com/repository/docker/felipewind/broker-front-end)

### Building the Docker images locally

Inside the root folder of the project, execute:
```
$ chmod +x ./run-with-local-build.sh
$ ./run-with-local-build.sh
```

After the first build, you can use the `run-after-local-build` script.

## Without docker-compose 

### Enter inside the `exchange-back-end` folder and type:
```
$ ./mvnw compile quarkus:dev -Ddebug=5006
```

Access http://localhost:8090/q/swagger-ui/

### Enter inside the `broker-back-end` folder and type:
```
$ ./mvnw compile quarkus:dev
```

Access http://localhost:8080/q/swagger-ui/

### Enter inside the `exchange-front-end` folder and type:
```
$ npm install
$ ng serve
```

Access http://localhost:4300

### Enter inside the `broker-front-end` folder and type:
```
$ npm install
$ ng serve
```

Access http://localhost:4200

# Images

Exchange Back End Swagger:
![image](./documentation/design/exchange-back-end-swagger.png)

Broker Back End Swagger:
![image](./documentation/design/broker-back-end-swagger.png)

Broker Front End - Orders:
![image](./documentation/design/broker-front-end-orders.png)

Exchange Front End - Orders:
![image](./documentation/design/exchange-front-end-orders.png)

# Help Queries

[What is FIX Protocol?](https://www.fixtrading.org/)

[What is QuickFIX/J?](https://www.quickfixj.org/)

[What is Quarkus?](https://quarkus.io/)

[What is Angular?](https://angular.io/)

[What is PostgreSQL?](https://www.postgresql.org/)

[What is Docker?](https://www.docker.com/)

[What is Docker Compose?](https://docs.docker.com/compose/)
