from fastapi import FastAPI, APIRouter, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from enum import Enum
import os
import logging
import uuid
import asyncio
import random
from pathlib import Path

ROOT_DIR = Path(__file__).parent
from dotenv import load_dotenv
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ.get('DB_NAME', 'fheap_db')]

# Create the main app
app = FastAPI(title="FHEAP - FHE Arbitrage Protection API", version="1.0.0")

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get('CORS_ORIGINS', '*').split(','),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ===== MODELS =====

class ProtectionStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    TRIGGERED = "triggered"
    MONITORING = "monitoring"

class DEXName(str, Enum):
    UNISWAP_V3 = "uniswap_v3"
    SUSHISWAP = "sushiswap"
    CURVE = "curve"
    BALANCER = "balancer"

class EncryptedPrice(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    dex_name: DEXName
    pool_address: str
    token_pair: str  # e.g., "ETH/USDC"
    encrypted_price: str  # Simulated FHE encrypted price
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    block_number: int

class ArbitrageOpportunity(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    pool_a: str
    pool_b: str
    dex_a: DEXName
    dex_b: DEXName
    token_pair: str
    encrypted_spread: str  # FHE encrypted spread
    encrypted_threshold: str  # FHE encrypted threshold
    opportunity_detected: bool
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    protection_triggered: bool = False

class ProtectionEvent(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    arbitrage_opportunity_id: str
    protection_status: ProtectionStatus
    encrypted_protection_fee: str  # FHE encrypted fee
    encrypted_mev_captured: str  # FHE encrypted MEV value
    tx_hash: Optional[str] = None
    gas_used: Optional[int] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class LPReward(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    lp_address: str
    pool_id: str
    encrypted_reward_amount: str  # FHE encrypted reward
    protection_event_id: str
    distribution_tx_hash: Optional[str] = None
    claimed: bool = False
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class FHEAPDashboard(BaseModel):
    total_mev_captured: str  # encrypted
    total_lp_rewards: str  # encrypted
    active_protections: int
    arbitrage_opportunities_detected: int
    protection_success_rate: float
    recent_events: List[ProtectionEvent]

# ===== FHE SIMULATION HELPERS =====

def simulate_fhe_encrypt(value: float) -> str:
    """Simulate FHE encryption - in real implementation this would use Fhenix FHE library"""
    # Create a deterministic but scrambled representation
    encrypted = f"fhe_enc_{int(value * 1000000)}_{random.randint(1000, 9999)}"
    return encrypted

def simulate_fhe_decrypt(encrypted_value: str) -> float:
    """Simulate FHE decryption - for demo purposes only"""
    try:
        # Extract the original value from our simulation format
        parts = encrypted_value.split('_')
        if len(parts) >= 3:
            return int(parts[2]) / 1000000.0
        return 0.0
    except:
        return 0.0

def simulate_fhe_add(enc_a: str, enc_b: str) -> str:
    """Simulate FHE addition"""
    dec_a = simulate_fhe_decrypt(enc_a)
    dec_b = simulate_fhe_decrypt(enc_b)
    return simulate_fhe_encrypt(dec_a + dec_b)

def simulate_fhe_sub(enc_a: str, enc_b: str) -> str:
    """Simulate FHE subtraction"""
    dec_a = simulate_fhe_decrypt(enc_a)
    dec_b = simulate_fhe_decrypt(enc_b)
    return simulate_fhe_encrypt(abs(dec_a - dec_b))

def simulate_fhe_gt(enc_a: str, enc_b: str) -> bool:
    """Simulate FHE greater than comparison"""
    dec_a = simulate_fhe_decrypt(enc_a)
    dec_b = simulate_fhe_decrypt(enc_b)
    return dec_a > dec_b

def simulate_fhe_mul(enc_value: str, multiplier: float) -> str:
    """Simulate FHE multiplication"""
    dec_value = simulate_fhe_decrypt(enc_value)
    return simulate_fhe_encrypt(dec_value * multiplier)

# ===== ARBITRAGE CALCULATION LOGIC =====

class ArbitrageCalculations:
    @staticmethod
    def calculate_encrypted_spread(price_a: str, price_b: str) -> str:
        """Calculate encrypted price spread between pools"""
        return simulate_fhe_sub(price_a, price_b)
    
    @staticmethod
    def has_arbitrage_opportunity(spread: str, threshold: str) -> bool:
        """Determine if arbitrage opportunity exists"""
        return simulate_fhe_gt(spread, threshold)
    
    @staticmethod
    def calculate_protection_fee(spread: str, volume: float, max_fee: str) -> str:
        """Calculate optimal protection fee"""
        # Dynamic fee based on spread size
        fee_rate = min(0.003, simulate_fhe_decrypt(spread) * 0.1)  # Max 0.3%
        protection_fee = simulate_fhe_encrypt(volume * fee_rate)
        
        # Cap at max fee
        if simulate_fhe_gt(protection_fee, max_fee):
            return max_fee
        return protection_fee
    
    @staticmethod
    def calculate_lp_rewards(captured_mev: str, lp_share: float = 0.8) -> str:
        """Compute LP reward distribution"""
        return simulate_fhe_mul(captured_mev, lp_share)

# ===== PRICE MONITORING =====

async def monitor_prices():
    """Simulate continuous price monitoring across DEXs"""
    pools = [
        {"dex": DEXName.UNISWAP_V3, "address": "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640", "pair": "ETH/USDC"},
        {"dex": DEXName.SUSHISWAP, "address": "0x397FF1542f962076d0BFE58eA045FfA2d347ACa0", "pair": "ETH/USDC"},
        {"dex": DEXName.CURVE, "address": "0xA0b86a33E6417efF66b9b4A3e0C6e31d5F5dd9C7", "pair": "ETH/USDC"},
    ]
    
    while True:
        try:
            for pool in pools:
                # Simulate price with small variations
                base_price = 2000 + random.uniform(-50, 50)  # ETH price around $2000
                encrypted_price = simulate_fhe_encrypt(base_price)
                
                price_data = EncryptedPrice(
                    dex_name=pool["dex"],
                    pool_address=pool["address"],
                    token_pair=pool["pair"],
                    encrypted_price=encrypted_price,
                    block_number=random.randint(19000000, 19999999)
                )
                
                await db.encrypted_prices.insert_one(price_data.dict())
                
                # Detect arbitrage opportunities
                await detect_arbitrage_opportunities(pool["pair"])
            
            await asyncio.sleep(5)  # Monitor every 5 seconds
            
        except Exception as e:
            logger.error(f"Error in price monitoring: {e}")
            await asyncio.sleep(10)

async def detect_arbitrage_opportunities(token_pair: str):
    """Detect arbitrage opportunities across DEXs"""
    try:
        # Get latest prices from all DEXs for this pair
        latest_prices = await db.encrypted_prices.find(
            {"token_pair": token_pair}
        ).sort("timestamp", -1).limit(10).to_list(10)
        
        if len(latest_prices) < 2:
            return
        
        # Compare prices between different DEXs
        for i in range(len(latest_prices)):
            for j in range(i + 1, len(latest_prices)):
                price_a = latest_prices[i]
                price_b = latest_prices[j]
                
                if price_a["dex_name"] != price_b["dex_name"]:
                    # Calculate encrypted spread
                    spread = ArbitrageCalculations.calculate_encrypted_spread(
                        price_a["encrypted_price"], 
                        price_b["encrypted_price"]
                    )
                    
                    # Set threshold (0.1% of price)
                    threshold = simulate_fhe_encrypt(simulate_fhe_decrypt(price_a["encrypted_price"]) * 0.001)
                    
                    # Check if arbitrage opportunity exists
                    has_opportunity = ArbitrageCalculations.has_arbitrage_opportunity(spread, threshold)
                    
                    if has_opportunity:
                        opportunity = ArbitrageOpportunity(
                            pool_a=price_a["pool_address"],
                            pool_b=price_b["pool_address"],
                            dex_a=DEXName(price_a["dex_name"]),
                            dex_b=DEXName(price_b["dex_name"]),
                            token_pair=token_pair,
                            encrypted_spread=spread,
                            encrypted_threshold=threshold,
                            opportunity_detected=True
                        )
                        
                        await db.arbitrage_opportunities.insert_one(opportunity.dict())
                        
                        # Trigger protection
                        await trigger_protection(opportunity)
                        
    except Exception as e:
        logger.error(f"Error detecting arbitrage: {e}")

async def trigger_protection(opportunity: ArbitrageOpportunity):
    """Trigger arbitrage protection mechanism"""
    try:
        # Simulate protection fee calculation
        volume = 100000  # $100k trade volume
        max_fee = simulate_fhe_encrypt(3000)  # $3k max fee
        
        protection_fee = ArbitrageCalculations.calculate_protection_fee(
            opportunity.encrypted_spread, volume, max_fee
        )
        
        # Simulate MEV capture
        mev_captured = simulate_fhe_mul(opportunity.encrypted_spread, volume)
        
        # Create protection event
        protection_event = ProtectionEvent(
            arbitrage_opportunity_id=opportunity.id,
            protection_status=ProtectionStatus.TRIGGERED,
            encrypted_protection_fee=protection_fee,
            encrypted_mev_captured=mev_captured,
            tx_hash=f"0x{random.randint(10**63, 10**64-1):x}",
            gas_used=random.randint(200000, 500000)
        )
        
        await db.protection_events.insert_one(protection_event.dict())
        
        # Distribute LP rewards
        await distribute_lp_rewards(protection_event)
        
        logger.info(f"Protection triggered for opportunity {opportunity.id}")
        
    except Exception as e:
        logger.error(f"Error triggering protection: {e}")

async def distribute_lp_rewards(protection_event: ProtectionEvent):
    """Distribute rewards to liquidity providers"""
    try:
        # Calculate LP rewards (80% of captured MEV)
        lp_reward_total = ArbitrageCalculations.calculate_lp_rewards(
            protection_event.encrypted_mev_captured
        )
        
        # Simulate LP addresses (in real implementation, get from pool data)
        lp_addresses = [
            f"0x{random.randint(10**39, 10**40-1):x}" for _ in range(5)
        ]
        
        # Distribute rewards equally among LPs
        reward_per_lp = simulate_fhe_mul(lp_reward_total, 1.0 / len(lp_addresses))
        
        for lp_address in lp_addresses:
            lp_reward = LPReward(
                lp_address=lp_address,
                pool_id=f"pool_{random.randint(1, 100)}",
                encrypted_reward_amount=reward_per_lp,
                protection_event_id=protection_event.id,
                distribution_tx_hash=f"0x{random.randint(10**63, 10**64-1):x}"
            )
            
            await db.lp_rewards.insert_one(lp_reward.dict())
        
        logger.info(f"LP rewards distributed for event {protection_event.id}")
        
    except Exception as e:
        logger.error(f"Error distributing LP rewards: {e}")

# ===== API ENDPOINTS =====

@api_router.get("/")
async def root():
    return {"message": "FHEAP - FHE Arbitrage Protection API"}

@api_router.get("/dashboard", response_model=FHEAPDashboard)
async def get_dashboard():
    """Get main dashboard data"""
    try:
        # Get recent protection events
        recent_events = await db.protection_events.find().sort("timestamp", -1).limit(10).to_list(10)
        
        # Calculate aggregated metrics
        total_events = await db.protection_events.count_documents({})
        active_protections = await db.protection_events.count_documents({"protection_status": "triggered"})
        total_opportunities = await db.arbitrage_opportunities.count_documents({})
        
        success_rate = (active_protections / total_opportunities * 100) if total_opportunities > 0 else 0
        
        # Simulate encrypted totals
        total_mev = simulate_fhe_encrypt(547829.43)  # Total MEV captured
        total_rewards = simulate_fhe_encrypt(438263.54)  # Total LP rewards
        
        dashboard = FHEAPDashboard(
            total_mev_captured=total_mev,
            total_lp_rewards=total_rewards,
            active_protections=active_protections,
            arbitrage_opportunities_detected=total_opportunities,
            protection_success_rate=round(success_rate, 2),
            recent_events=[ProtectionEvent(**event) for event in recent_events]
        )
        
        return dashboard
        
    except Exception as e:
        logger.error(f"Error getting dashboard: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@api_router.get("/prices", response_model=List[EncryptedPrice])
async def get_latest_prices(limit: int = 20):
    """Get latest encrypted prices from all DEXs"""
    try:
        prices = await db.encrypted_prices.find().sort("timestamp", -1).limit(limit).to_list(limit)
        return [EncryptedPrice(**price) for price in prices]
    except Exception as e:
        logger.error(f"Error getting prices: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@api_router.get("/arbitrage-opportunities", response_model=List[ArbitrageOpportunity])
async def get_arbitrage_opportunities(limit: int = 50):
    """Get detected arbitrage opportunities"""
    try:
        opportunities = await db.arbitrage_opportunities.find().sort("timestamp", -1).limit(limit).to_list(limit)
        return [ArbitrageOpportunity(**opp) for opp in opportunities]
    except Exception as e:
        logger.error(f"Error getting arbitrage opportunities: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@api_router.get("/protection-events", response_model=List[ProtectionEvent])
async def get_protection_events(limit: int = 50):
    """Get protection events"""
    try:
        events = await db.protection_events.find().sort("timestamp", -1).limit(limit).to_list(limit)
        return [ProtectionEvent(**event) for event in events]
    except Exception as e:
        logger.error(f"Error getting protection events: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@api_router.get("/lp-rewards/{lp_address}", response_model=List[LPReward])
async def get_lp_rewards(lp_address: str):
    """Get LP rewards for a specific address"""
    try:
        rewards = await db.lp_rewards.find({"lp_address": lp_address}).sort("timestamp", -1).to_list(100)
        return [LPReward(**reward) for reward in rewards]
    except Exception as e:
        logger.error(f"Error getting LP rewards: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@api_router.get("/statistics")
async def get_statistics():
    """Get protection statistics"""
    try:
        # Time-based statistics
        last_24h = datetime.utcnow() - timedelta(hours=24)
        
        total_opportunities = await db.arbitrage_opportunities.count_documents({})
        opportunities_24h = await db.arbitrage_opportunities.count_documents({
            "timestamp": {"$gte": last_24h}
        })
        
        total_protections = await db.protection_events.count_documents({})
        protections_24h = await db.protection_events.count_documents({
            "timestamp": {"$gte": last_24h}
        })
        
        return {
            "total_arbitrage_opportunities": total_opportunities,
            "arbitrage_opportunities_24h": opportunities_24h,
            "total_protections_triggered": total_protections,
            "protections_triggered_24h": protections_24h,
            "protection_success_rate": round((total_protections / total_opportunities * 100) if total_opportunities > 0 else 0, 2),
            "encrypted_total_mev_captured": simulate_fhe_encrypt(1547829.43),
            "encrypted_total_lp_rewards_distributed": simulate_fhe_encrypt(1238263.54),
            "average_protection_response_time_ms": 12.3
        }
        
    except Exception as e:
        logger.error(f"Error getting statistics: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

# Include the router in the main app
app.include_router(api_router)

# Background task to start price monitoring
@app.on_event("startup")
async def startup_event():
    """Start background price monitoring"""
    asyncio.create_task(monitor_prices())

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)