###
# Tests the driver cursor API
###

import unittest
from os import getenv
from sys import path, argv
path.append("../../drivers/python")

import rethinkdb as r

num_rows = int(argv[2])
port = int(argv[1])

class TestCursor(unittest.TestCase):

    def setUp(self):
        c = r.connect(port=port)
        tbl = r.table('test')
        self.cur = tbl.run(c)

    def test_type(self):
        self.assertEqual(type(self.cur), r.Cursor)

    def test_count(self):
        i = 0
        for row in self.cur:
            i += 1

        self.assertEqual(i, num_rows)

if __name__ == '__main__':
    print "Testing cursor for %d rows" % num_rows
    suite = unittest.TestSuite()
    loader = unittest.TestLoader()
    suite.addTest(loader.loadTestsFromTestCase(TestCursor))
    unittest.TextTestRunner(verbosity=1).run(suite)
