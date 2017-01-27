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
        time.sleep(2)
        driver.title.index("Login - OpenStack Dashboard")
        elem = driver.find_element_by_name("username")
        elem.send_keys(os.environ["OS_USERNAME"])
        elem = driver.find_element_by_name("password")
        elem.send_keys(os.environ["OS_PASSWORD"])
        elem.send_keys(Keys.RETURN)
        time.sleep(2)

    def test_instances(self):
        driver = self.driver
        driver.get("%s/project/instances/" % os.environ["OS_HORIZON"])
        driver.title.index("Instances - OpenStack Dashboard")
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
        i.test_instances()
    except Exception:
        print("Tearing down due to error.")
        try:
            i.tearDown()
        except Exception:
            pass
        raise
    else:
        i.tearDown()
        
