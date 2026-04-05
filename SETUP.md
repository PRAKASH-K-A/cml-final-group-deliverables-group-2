# FIX Trading Simulator - Setup Guide

## Prerequisites

- **Java 11+** - For running Quarkus back-end services
- **Maven 3.6+** - For building Java projects
- **Node.js 16+** - For building Angular front-ends
- **npm 7+** - For managing Node.js dependencies
- **Docker & Docker Compose** - For containerized deployment
- **PostgreSQL 13+** - For database (can run via Docker)
- **Git** - For version control

## Project Structure

```
fix-trading-simulator/
├── exchange-back-end/       # FIX Acceptor (Exchange) - Quarkus
├── exchange-front-end/      # Exchange UI - Angular
├── broker-back-end/         # FIX Initiator (Broker) - Quarkus
├── broker-front-end/        # Broker UI - Angular
├── database/                # Database schemas
├── config/                  # Configuration files
├── docker-compose.yml       # Multi-container orchestration
└── README.md               # This file
```

## Installation

### 1. Install Dependencies

**Java (JDK 11)**
```bash
# macOS
brew install openjdk@11

# Linux (Ubuntu/Debian)
sudo apt-get install openjdk-11-jdk

# Windows - Download from https://adoptopenjdk.net/
```

**Maven**
```bash
# macOS
brew install maven

# Linux (Ubuntu/Debian)
sudo apt-get install maven

# Windows - Download from https://maven.apache.org/download.cgi
```

**Node.js**
```bash
# macOS
brew install node

# Linux (Ubuntu/Debian)
sudo apt-get install nodejs npm

# Windows - Download from https://nodejs.org/
```

**Docker & Docker Compose**
- Download from https://www.docker.com/products/docker-desktop

### 2. Start PostgreSQL

**Option A: Local Installation**
```bash
# macOS
brew install postgresql
brew services start postgresql

# Linux
sudo apt-get install postgresql
sudo systemctl start postgresql
```

**Option B: Docker**
```bash
docker run -d --name postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:13
```

### 3. Initialize Database

```bash
# Create database and schema
psql -U postgres < database/schema.sql
psql -U postgres fix_trading_simulator < database/sample-data.sql
```

## Building the Project

### Build Exchange Back-End

```bash
cd exchange-back-end
./mvnw clean package
cd ..
```

### Build Broker Back-End

```bash
cd broker-back-end
./mvnw clean package
cd ..
```

### Build Exchange Front-End

```bash
cd exchange-front-end
npm install
npm run build
cd ..
```

### Build Broker Front-End

```bash
cd broker-front-end
npm install
npm run build
cd ..
```

### Build All (Automated)

```bash
./scripts/build/build.sh
```

## Running the Application

### Option 1: Development Mode

**Terminal 1 - Exchange Back-End**
```bash
cd exchange-back-end
./mvnw quarkus:dev
```

**Terminal 2 - Broker Back-End**
```bash
cd broker-back-end
./mvnw quarkus:dev
```

**Terminal 3 - Exchange Front-End**
```bash
cd exchange-front-end
npm start
```

**Terminal 4 - Broker Front-End**
```bash
cd broker-front-end
npm start
```

### Option 2: Docker Compose

```bash
# Build images
docker-compose build

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## Access the Application

- **Exchange Platform**: http://localhost:4201
- **Broker Platform**: http://localhost:4200
- **Exchange API**: http://localhost:8090
  - Swagger UI: http://localhost:8090/q/swagger-ui/
- **Broker API**: http://localhost:8080
  - Swagger UI: http://localhost:8080/q/swagger-ui/
- **Database**: localhost:5432

## Application Ports

| Service | Port | Type |
|---------|------|------|
| Exchange Back-End | 8090 | REST API |
| Broker Back-End | 8080 | REST API |
| Exchange Front-End | 4201 | Angular App |
| Broker Front-End | 4200 | Angular App |
| FIX Acceptor (Exchange) | 9876 | FIX Protocol |
| PostgreSQL | 5432 | Database |

## Architecture

### Exchange (Acceptor)
- Listens for FIX connections on port 9876
- Processes incoming NewOrderSingle and OrderCancelRequest messages
- Sends ExecutionReport messages to connected clients
- Provides REST API at port 8090

### Broker (Initiator)
- Connects to Exchange FIX Acceptor at localhost:9876
- Sends orders and receives execution reports
- Provides REST API at port 8080
- Acts as client to the Exchange

### Data Flow
1. Client submits order via Broker front-end or REST API
2. Broker sends NewOrderSingle message to Exchange via FIX
3. Exchange receives and validates order
4. Exchange sends ExecutionReport to Broker
5. Broker updates order status and notifies client via WebSocket
6. Front-end receives update and refreshes UI

## Configuration

### Exchange Back-End (exchange-back-end/src/main/resources/application.properties)
```properties
quarkus.datasource.jdbc.url=jdbc:postgresql://localhost:5432/fix_trading_simulator
quarkus.datasource.username=postgres
quarkus.datasource.password=postgres
quarkus.http.port=8090
```

### Broker Back-End (broker-back-end/src/main/resources/application.properties)
```properties
quarkus.datasource.jdbc.url=jdbc:postgresql://localhost:5432/fix_trading_simulator
quarkus.datasource.username=postgres
quarkus.datasource.password=postgres
quarkus.http.port=8080
```

## FIX Configuration

Session settings are defined in `config/quickfix.cfg`:

```
[DEFAULT]
HeartBtInt=30
SenderCompID=EXCHANGE
TargetCompID=BROKER
BeginString=FIX.4.4

[SESSION]
SocketAcceptPort=9876        # Exchange listens here
```

## API Documentation

### Order Management

**Create Order**
```bash
POST /orders
Content-Type: application/json

{
  "symbol": "AAPL",
  "side": "1",
  "quantity": 100,
  "price": 150.00,
  "orderType": "2",
  "timeInForce": "0"
}
```

**Get Orders**
```bash
GET /orders
```

**Get Order by ID**
```bash
GET /orders/{clOrdID}
```

**Cancel Order**
```bash
DELETE /orders/{clOrdID}
```

### Session Management

**Get Session Status**
```bash
GET /session
```

**Logon (Broker)**
```bash
POST /session/logon
```

**Logout (Broker)**
```bash
POST /session/logout
```

## WebSocket Connections

Real-time order updates are available via WebSocket:

```javascript
const ws = new WebSocket('ws://localhost:8090/socket/order');

ws.onmessage = (event) => {
  const orderUpdate = JSON.parse(event.data);
  console.log('Order updated:', orderUpdate);
};
```

## Testing

### Manual Testing with curl

```bash
# Create an order
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "symbol": "AAPL",
    "side": "1",
    "quantity": 100,
    "price": 150.00,
    "orderType": "2",
    "timeInForce": "0"
  }'

# Get all orders
curl http://localhost:8080/orders

# Get specific order
curl http://localhost:8080/orders/ABC123

# Cancel order
curl -X DELETE http://localhost:8080/orders/ABC123
```

## Troubleshooting

### Database Connection Issues
- Verify PostgreSQL is running: `psql -U postgres -l`
- Check connection string in application.properties
- Ensure database schema has been initialized

### FIX Connection Issues
- Check that Exchange back-end is running on port 9876
- Verify firewall is not blocking port 9876
- Check broker's quickfix.cfg for correct target host/port

### Build Errors
- Ensure Java 11+ is installed: `java -version`
- Clear Maven cache: `./mvnw clean`
- Update dependencies: `./mvnw clean dependency:resolve`

### Port Already in Use
```bash
# Find and kill process on port
lsof -i :8090        # Exchange
lsof -i :8080        # Broker
lsof -i :9876        # FIX Acceptor
```

## Performance Tips

1. **Database Indexes**: Already created on:
   - orders.symbol
   - orders.status
   - orders.client_id
   - orders.created_at

2. **Connection Pooling**: Configured via Quarkus DataSource

3. **Message Batching**: Orders are stored and processed asynchronously

4. **WebSocket Updates**: Real-time notifications minimize polling

## Next Steps

1. Implement DAO layer for persistence
2. Add more REST endpoints
3. Create Angular components for order management
4. Deploy to production environment
5. Add monitoring and alerting

## Support

For issues or questions, please refer to:
- Quarkus Documentation: https://quarkus.io/
- QuickFIX/J Documentation: https://www.quickfixj.org/
- Angular Documentation: https://angular.io/
- PostgreSQL Documentation: https://www.postgresql.org/docs/

## License

This project is provided as-is for educational purposes.
