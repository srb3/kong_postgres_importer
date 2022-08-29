from selenium import webdriver
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.common.by import By
import time
import os

kong_manager_url = "http://localhost:8002"

name = os.environ["KONG_ADMIN_USER"]
email = os.environ["KONG_ADMIN_EMAIL"]
password = os.environ["KONG_ADMIN_PASS"]

print("Testing login for user: " + name + " to: " + kong_manager_url)
options = Options()
options.headless = True
driver = webdriver.Firefox(options=options)
driver.get(kong_manager_url)
time.sleep(2)

print(driver.title)
assert "Login | Kong Manager" in driver.title
elem = driver.find_element(By.ID, "username")
elem.clear()
elem.send_keys(name)
elem.send_keys(Keys.RETURN)
time.sleep(2)

print(driver.title)
assert "Sign in to your account" in driver.title
elem = driver.find_element(By.NAME, "loginfmt")
elem.clear()
elem.send_keys(email)
elem.send_keys(Keys.RETURN)

print(driver.title)
assert "Sign in to your account" in driver.title
time.sleep(2)
elem = driver.find_element(By.NAME, "passwd")
elem.send_keys(password)
time.sleep(2)

elem = driver.find_element(By.ID, "idSIButton9")
elem.click()

print(driver.title)
assert "Sign in to your account" in driver.title
time.sleep(2)
link_text = "Skip for now (14 days until this is required)"
driver.find_element(By.LINK_TEXT, link_text).click()

print(driver.title)
assert "Sign in to your account" in driver.title
time.sleep(2)
elem = driver.find_element(By.ID, "idSIButton9")
elem.click()

time.sleep(2)
assert "Dashboard | Kong Manager" in driver.title
print("Login Success for: " + name)
driver.close()
