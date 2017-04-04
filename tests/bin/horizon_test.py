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
from selenium.common.exceptions import TimeoutException
from selenium.common.exceptions import WebDriverException
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait
import time


class Instances(object):

    def getDriver(self):
        count = 0
        while(True):
            try:
                ce = "http://%s:4444/wd/hub" % os.environ["HUB"]
                driver = webdriver.Remote(
                    command_executor=ce,
                    desired_capabilities={
                        "browserName": os.environ.get("browser", "firefox"),
                        "platform": "Linux"
                    }
                )
                return driver
            except WebDriverException as e:
                s = "%s" % e
                print("Got exception %s" % s)
                print("%s" % dir(s))
                if "Empty pool of VM for setup Capabilities" not in s:
                    raise
                time.sleep(5)
            if count == 60:
                raise Exception("Time out trying to get a browser")
            count += 1

    def setUp(self):
        self.driver = self.getDriver()
        print("Got driver")
        self.driver.get(os.environ["OS_HORIZON"])
        try:
            delay = 5
            element_present = EC.presence_of_element_located((By.NAME,
                                                              'username'))
            WebDriverWait(self.driver, delay).until(element_present)
            self.driver.title.index("Login - OpenStack Dashboard")
            elem = self.driver.find_element_by_name("username")
            elem.send_keys(os.environ["OS_USERNAME"])
            elem = self.driver.find_element_by_name("password")
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
            s = 'Instances - OpenStack Dashboard'
            element_present = EC.title_contains(s)
            WebDriverWait(self.driver, delay).until(element_present)
            print("Ok")
        except TimeoutException:
            print("Loading took too much time!")
            raise

    def screenshot(self):
        if self.driver:
            screenshot = os.path.join(os.environ['WORKSPACE'],
                                      'logs', 'horizon.png')
            self.driver.get_screenshot_as_file(screenshot)

    def tearDown(self):
        if self.driver:
            self.driver.close()
            self.driver.quit()

if __name__ == "__main__":
    i = Instances()
    try:
        i.setUp()
        i.testInstances()
    except Exception as e:
        print("Tearing down due to error. %s" % e)
        try:
            i.screenshot()
            i.tearDown()
        except Exception as e:
            print("Got another exception. %s" % e)
            pass
        pass
    else:
        i.tearDown()
