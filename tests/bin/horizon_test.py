#!/usr/bin/env python
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import os
from selenium import webdriver
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By
from selenium.common.exceptions import TimeoutException
import time


class Instances(object):

    def setUp(self):
        self.driver = None
        ce = "http://%s:4444/wd/hub" % os.environ["HUB"]
        driver = webdriver.Remote(
            command_executor=ce,
            desired_capabilities={
                "browserName": os.environ.get("browser", "firefox"),
                "platform": "Linux"
            }
        )
        self.driver = driver
        print("Got driver")
        driver.get(os.environ["OS_HORIZON"])
        try:
            delay = 5
            element_present = EC.presence_of_element_located((By.Name,
                                                              'username'))
            WebDriverWait(self.driver, delay).until(element_present)
            driver.title.index("Login - OpenStack Dashboard")
            elem = driver.find_element_by_name("username")
            elem.send_keys(os.environ["OS_USERNAME"])
            elem = driver.find_element_by_name("password")
            elem.send_keys(os.environ["OS_PASSWORD"])
            elem.send_keys(Keys.RETURN)
        except TimeoutException:
            print("Loading took too much time!")
            raise
        time.sleep(2)

    def testInstances(self):
        driver = self.driver
        driver.get("%s/project/instances/" % os.environ["OS_HORIZON"])
        try:
            delay = 5
            element_present = EC.title_contains('Instances - OpenStack Dashboard')
            WebDriverWait(self.driver, delay).until(element_present)
            print("Ok")
        except TimeoutException:
            print("Loading took too much time!")
            raise

    def screenshot(self):
        if self.driver:
            screenshot = os.path.join(os.environ['WORKSPACE'],
                                      'logs', 'horizon.png')
            driver.get_screenshot_as_file(screenshot)

    def tearDown(self):
        if self.driver:
            self.driver.close()
            self.driver.quit()

if __name__ == "__main__":
    i = Instances()
    try:
        i.setUp()
        i.testInstances()
    except Exception:
        print("Tearing down due to error.")
        i.screenshot()
        try:
            i.tearDown()
        except Exception:
            pass
        raise
    else:
        i.tearDown()
