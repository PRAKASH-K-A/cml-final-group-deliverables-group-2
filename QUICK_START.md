# Quick Start Guide

## 1. Clone/Access the Project
```bash
cd c:\Users\Aarav\OneDrive\Desktop\cmltest\fix-trading-simulator
```

## 2. Start PostgreSQL
```bash
# Option A: Docker
docker run -d --name postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:13

# Wait 10 seconds for DB to start
sleep 10

# Option B: Local PostgreSQL
psql -U postgres
```

## 3. Initialize Database
```bash
psql -U postgres < database/schema.sql
psql -U postgres fix_trading_simulator < database/sample-data.sql
```

## 4. Build All Components
```bash
./build.sh
# OR build individually:
# cd exchange-back-end && ./mvnw clean package
# cd broker-back-end && ./mvnw clean package
# cd exchange-front-end && npm install && npm run build
# cd broker-front-end && npm install && npm run build
```

## 5. Run Services (Development Mode - Recommended)

### Option 0: Windows One-Command Startup

```powershell
cd c:\Users\Aarav\OneDrive\Desktop\cmltest\fix-trading-simulator
.\start-local.ps1
```

This starts services in the right order (exchange first, then broker), and opens front-ends on:
- Broker UI: http://localhost:4200
- Exchange UI: http://localhost:4201

### Option A: Individual Terminals (Easier for Development)

**Terminal 1 - Exchange Back-End (Port 8090)**
```bash
cd exchange-back-end
./mvnw quarkus:dev
```

**Terminal 2 - Broker Back-End (Port 8080)**
```bash
cd broker-back-end
./mvnw quarkus:dev
```

**Terminal 3 - Exchange Front-End (Port 4201)**
```bash
cd exchange-front-end
npm start
```

**Terminal 4 - Broker Front-End (Port 4200)**
```bash
cd broker-front-end
npm start
```

Then open:
- Exchange: http://localhost:4201
- Broker: http://localhost:4200

### Option B: Docker Compose (Full Stack)

```bash
# Build and start all services
docker-compose up -d

# Force fresh images from local source (recommended after code changes)
docker-compose build --no-cache
docker-compose up -d

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

Same URLs above will work.

## 6. Test the FIX Connection

```bash
# Create order on Broker (via REST API)
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "symbol": "AAPL",
    "side": "1",
    "quantity": 100,
    "price": 150.50,
    "orderType": "2",
    "timeInForce": "0"
  }'

# Get all orders
curl http://localhost:8080/orders

# View Exchange API docs
open http://localhost:8090/q/swagger-ui/
open http://localhost:8080/q/swagger-ui/
```

## 7. Monitor Services

```bash
# Check service status
ps aux | grep java
ps aux | grep npm

# View logs
docker-compose logs -f exchange-back-end
docker-compose logs -f broker-back-end

# Database
psql -U postgres fix_trading_simulator
SELECT * FROM orders;
```

## Architecture Quick Reference

```
Broker Client
    ↓
Broker Front-End (Angular 13, Port 4200)
    ↓ REST/WebSocket
Broker Back-End (Quarkus, Port 8080)
    ↓ FIX Protocol
Exchange Back-End (Quarkus, Port 8090, FIX on 9876)
    ↓
PostgreSQL Database (Port 5432)
```

## Default Ports

| Service | Port | Type |
|---------|------|------|
| Exchange Front-End | 4201 | HTTP (Angular UI) |
| Broker Front-End | 4200 | HTTP (Angular UI) |
| Exchange Back-End API | 8090 | HTTP REST |
| Broker Back-End API | 8080 | HTTP REST |
| FIX Acceptor (Exchange) | 9876 | TCP FIX |
| PostgreSQL | 5432 | TCP DB |

## Stopping Services

```bash
# Docker Compose
docker-compose down

# Individual services (in each terminal)
Ctrl+C

# Kill stuck processes
lsof -i :8090
kill -9 <PID>
```

## Folder Structure (Quick Reference)

```
fix-trading-simulator/
├── exchange-back-end/    ← Quarkus REST API (FIX Acceptor)
├── broker-back-end/      ← Quarkus REST API (FIX Initiator)
├── exchange-front-end/   ← Angular UI on port 4201
├── broker-front-end/     ← Angular UI on port 4200
├── database/             ← PostgreSQL schemas
├── config/               ← FIX & app configuration
└── docker-compose.yml    ← Multi-container definition
```

## Common Tasks

### Start a fresh development session
```bash
# In project root
docker-compose down -v    # Clean volumes if needed
./build.sh
docker-compose up -d
```

### Monitor WebSocket events
```bash
# Browser console in Angular app (F12)
const ws = new WebSocket('ws://localhost:8090/socket/order');
ws.onmessage = e => console.log(JSON.parse(e.data));
```

### View database schema
```bash
psql -U postgres fix_trading_simulator
\dt              # List tables
\d orders        # Describe orders table
SELECT * FROM orders;  # View data
```

### Reset database
```bash
dropdb -U postgres fix_trading_simulator
psql -U postgres < database/schema.sql
psql -U postgres fix_trading_simulator < database/sample-data.sql
```

## Troubleshooting

### Port already in use
```bash
# Kill process on port
lsof -i :8090 && kill -9 <PID>
```

### Can't connect to database
```bash
# Check PostgreSQL running
psql -U postgres -l

# If using Docker
docker ps | grep postgres
docker logs postgres
```

### FIX connection fails
```bash
# Ensure Exchange back-end is running and listening
netstat -an | grep 9876  # Should show LISTEN

# Restart Broker back-end
```

### Front-end can't connect to API
```bash
# Check proxy configuration (exchange-front-end/proxy.conf.json)
# Should point to http://localhost:8090 for exchange
# Should point to http://localhost:8080 for broker
```

## Next Steps

1. **Explore the UI**: Open http://localhost:4200 (Broker)
2. **Check API Docs**: Open http://localhost:8090/q/swagger-ui/
3. **Submit an Order**: Use the REST API or Angular form
4. **Monitor WebSocket**: Watch real-time updates in browser console
5. **Check Database**: View orders in PostgreSQL

## For More Information

- See `README.md` for full documentation
- See `SETUP.md` for detailed setup instructions
- See `COMPLETION_SUMMARY.md` for what's been created
- See `CONTRIBUTING.md` for development guidelines

---

**Happy Trading! 🚀**
