/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Aug 6, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module tests.Object;

import orange.serialization.Serializer;
import orange.serialization.archives.XmlArchive;
import orange.test.UnitTester;
import tests.Util;

Serializer serializer;
XmlArchive!(char) archive;

class A
{
    override equals_t opEquals (Object other)
    {
        if (auto o = cast(A) other)
            return true;

        return false;
    }
}

A a;

unittest
{
    archive = new XmlArchive!(char);
    serializer = new Serializer(archive);

    a = new A;

    describe("serialize object") in {
        it("should return a serialized object") in {
auto expected = q"xml
<?xml version="1.0" encoding="UTF-8"?>
<archive version="1.0.0" type="org.dsource.orange.xml">
    <data>
        <object runtimeType="tests.Object.A" type="tests.Object.A" key="0" id="0"/>
    </data>
</archive>
xml";
            serializer.reset;
            serializer.serialize(a);

            assert(expected.equalToXml(archive.data));
        };
    };

    describe("deserialize object") in {
        it("should return a deserialized object equal to the original object") in {
            auto aDeserialized = serializer.deserialize!(A)(archive.untypedData);
            assert(a == aDeserialized);
        };
    };
}
