import LampBoardCore
import TestKit

enum PathNormalizerSuite {
    static let suite = TestSuite("Path normalization", [

        TestCase("Strips the trailing slash") { t in
            t.expectEqual(PathNormalizer.normalize("/Users/sam/dev/"), "/Users/sam/dev")
        },

        TestCase("Collapses doubled slashes") { t in
            t.expectEqual(PathNormalizer.normalize("/Users//sam///dev"), "/Users/sam/dev")
        },

        TestCase("Leaves an already normalized path alone") { t in
            t.expectEqual(PathNormalizer.normalize("/Users/sam/dev"), "/Users/sam/dev")
        },

        TestCase("Preserves the root") { t in
            t.expectEqual(PathNormalizer.normalize("/"), "/")
        },

        TestCase("Handles the empty string") { t in
            t.expectEqual(PathNormalizer.normalize(""), "")
        },

        TestCase("A path is a descendant of itself") { t in
            t.expect(PathNormalizer.isDescendant("/a/b", of: "/a/b"), "/a/b should contain itself")
        },

        TestCase("Recognizes a direct descendant") { t in
            t.expect(PathNormalizer.isDescendant("/a/b/c", of: "/a/b"), "/a/b/c is inside /a/b")
        },

        TestCase("Recognizes a deep descendant") { t in
            t.expect(PathNormalizer.isDescendant("/a/b/c/d/e", of: "/a/b"), "/a/b/c/d/e is inside /a/b")
        },

        // The case a string-prefix comparison would get wrong.
        TestCase("A name sharing the prefix is not a descendant") { t in
            t.expect(
                !PathNormalizer.isDescendant("/dev/lampboard-old", of: "/dev/lampboard"),
                "lampboard-old is not inside lampboard"
            )
        },

        TestCase("The parent is not a descendant of the child") { t in
            t.expect(!PathNormalizer.isDescendant("/a", of: "/a/b"), "/a is not inside /a/b")
        },

        TestCase("Descendancy ignores trailing slashes") { t in
            t.expect(PathNormalizer.isDescendant("/a/b/c/", of: "/a/b/"), "trailing slashes don't count")
        },
    ])
}
