#!/bin/env python

import os
import time
from selenium import webdriver
from selenium.webdriver.common.keys import Keys


class Instances(object):

    def setUp(self):
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

    def tearDown(self):
        self.driver.close()
        self.driver.quit()

if __name__ == "__main__":
    i = Instances()
    try:
        i.setUp()
        i.test_instances()
    except Exception:
        print("tearing down")
        i.tearDown()
        raise
    i.tearDown()
