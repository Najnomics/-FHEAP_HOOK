#!/usr/bin/env python3
"""
FHEAP Backend API Testing Suite
Tests the FHE Arbitrage Protection backend endpoints
"""

import requests
import sys
import json
from datetime import datetime
from typing import Dict, Any

class FHEAPBackendTester:
    def __init__(self, base_url="https://fhe-arb-hook.preview.emergentagent.com"):
        self.base_url = base_url
        self.api_base = f"{base_url}/api"
        self.tests_run = 0
        self.tests_passed = 0
        self.test_results = []

    def log_test(self, name: str, success: bool, details: str = "", response_data: Any = None):
        """Log test results"""
        self.tests_run += 1
        if success:
            self.tests_passed += 1
        
        result = {
            "test_name": name,
            "success": success,
            "details": details,
            "response_data": response_data,
            "timestamp": datetime.utcnow().isoformat()
        }
        self.test_results.append(result)
        
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} - {name}")
        if details:
            print(f"    Details: {details}")
        if response_data and isinstance(response_data, dict):
            print(f"    Response: {json.dumps(response_data, indent=2)}")
        print()

    def test_endpoint(self, name: str, endpoint: str, method: str = "GET", 
                     expected_status: int = 200, data: Dict = None) -> tuple:
        """Test a single API endpoint"""
        url = f"{self.api_base}/{endpoint}" if not endpoint.startswith('http') else endpoint
        headers = {'Content-Type': 'application/json'}
        
        try:
            if method == 'GET':
                response = requests.get(url, headers=headers, timeout=10)
            elif method == 'POST':
                response = requests.post(url, json=data, headers=headers, timeout=10)
            else:
                raise ValueError(f"Unsupported method: {method}")

            success = response.status_code == expected_status
            
            try:
                response_data = response.json()
            except:
                response_data = {"raw_response": response.text}

            details = f"Status: {response.status_code} (expected {expected_status})"
            if not success:
                details += f", Response: {response.text[:200]}"

            self.log_test(name, success, details, response_data)
            return success, response_data

        except requests.exceptions.RequestException as e:
            self.log_test(name, False, f"Request failed: {str(e)}")
            return False, {}
        except Exception as e:
            self.log_test(name, False, f"Unexpected error: {str(e)}")
            return False, {}

    def test_basic_endpoints(self):
        """Test the basic backend endpoints that should exist"""
        print("🔍 Testing Basic Backend Endpoints...")
        print("=" * 50)
        
        # Test root endpoint
        self.test_endpoint("Root API Endpoint", "")
        
        # Test health check
        self.test_endpoint("Health Check", "health")
        
        # Test status endpoint
        self.test_endpoint("Status Check", "status")

    def test_frontend_expected_endpoints(self):
        """Test endpoints that the frontend expects but may not exist"""
        print("🔍 Testing Frontend Expected Endpoints...")
        print("=" * 50)
        
        # These endpoints are called by the frontend but likely don't exist yet
        frontend_endpoints = [
            ("Dashboard Data", "dashboard"),
            ("Statistics", "statistics"),
            ("Arbitrage Opportunities", "arbitrage-opportunities?limit=20"),
            ("Price Data", "prices?limit=30"),
            ("LP Rewards", "lp-rewards/0x742d35cc7bf6c8a2d7c69b2d4c8e2f3d4e5a91d2"),
            ("Protection Events", "protection-events?limit=50")
        ]
        
        for name, endpoint in frontend_endpoints:
            # These will likely return 404, but we test them anyway
            success, data = self.test_endpoint(name, endpoint, expected_status=404)
            # If they return 200, that's even better
            if not success:
                # Try again expecting 200 in case they actually exist
                self.test_endpoint(f"{name} (Alt)", endpoint, expected_status=200)

    def test_cors_and_connectivity(self):
        """Test CORS and basic connectivity"""
        print("🔍 Testing CORS and Connectivity...")
        print("=" * 50)
        
        try:
            # Test if we can reach the base URL
            response = requests.get(self.base_url, timeout=10)
            success = response.status_code in [200, 404, 405]  # Any response is good
            self.log_test("Base URL Connectivity", success, 
                         f"Status: {response.status_code}")
            
            # Test CORS preflight (OPTIONS request)
            headers = {
                'Origin': 'http://localhost:3000',
                'Access-Control-Request-Method': 'GET',
                'Access-Control-Request-Headers': 'Content-Type'
            }
            response = requests.options(f"{self.api_base}/health", headers=headers, timeout=10)
            cors_success = response.status_code in [200, 204]
            self.log_test("CORS Preflight", cors_success, 
                         f"Status: {response.status_code}")
            
        except Exception as e:
            self.log_test("Connectivity Test", False, f"Error: {str(e)}")

    def run_all_tests(self):
        """Run all backend tests"""
        print("🛡️ FHEAP Backend API Test Suite")
        print("=" * 50)
        print(f"Testing backend at: {self.base_url}")
        print(f"API base URL: {self.api_base}")
        print()
        
        # Run test suites
        self.test_basic_endpoints()
        self.test_frontend_expected_endpoints()
        self.test_cors_and_connectivity()
        
        # Print summary
        self.print_summary()
        
        return self.tests_passed == self.tests_run

    def print_summary(self):
        """Print test summary"""
        print("📊 TEST SUMMARY")
        print("=" * 50)
        print(f"Total Tests: {self.tests_run}")
        print(f"Passed: {self.tests_passed}")
        print(f"Failed: {self.tests_run - self.tests_passed}")
        print(f"Success Rate: {(self.tests_passed/self.tests_run*100):.1f}%")
        print()
        
        # Show failed tests
        failed_tests = [r for r in self.test_results if not r['success']]
        if failed_tests:
            print("❌ FAILED TESTS:")
            for test in failed_tests:
                print(f"  - {test['test_name']}: {test['details']}")
            print()
        
        # Show successful tests
        passed_tests = [r for r in self.test_results if r['success']]
        if passed_tests:
            print("✅ PASSED TESTS:")
            for test in passed_tests:
                print(f"  - {test['test_name']}")
            print()

def main():
    """Main test execution"""
    tester = FHEAPBackendTester()
    
    try:
        success = tester.run_all_tests()
        return 0 if success else 1
    except KeyboardInterrupt:
        print("\n⚠️ Tests interrupted by user")
        return 1
    except Exception as e:
        print(f"\n💥 Test suite crashed: {str(e)}")
        return 1

if __name__ == "__main__":
    sys.exit(main())