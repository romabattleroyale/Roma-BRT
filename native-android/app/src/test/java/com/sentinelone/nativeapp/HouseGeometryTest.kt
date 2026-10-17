package com.sentinelone.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HouseGeometryTest {
    @Test
    fun openingsStayInsideWallsAndDoNotOverlap() {
        val result = normalizeOpenings(
            listOf(
                HouseOpening(wall = "Nord", type = "Porta", offset = -0.5f, width = 1.5f, height = 2.05f),
                HouseOpening(wall = "Nord", type = "Finestra", offset = 0.4f, width = 1.2f, height = 1.2f),
                HouseOpening(wall = "Nord", type = "Porta", offset = 3.5f, width = 2f, height = 2.05f),
                HouseOpening(wall = "Est", type = "Finestra", offset = 3.9f, width = 1.2f, height = 1.2f)
            ),
            roomWidth = 4f,
            roomDepth = 3f
        )

        assertEquals(3, result.size)
        result.filter { it.wall == "Nord" }.forEach { opening ->
            assertTrue(opening.offset >= 0f)
            assertTrue(opening.offset + opening.width <= 4.001f)
        }
        val north = result.filter { it.wall == "Nord" }.sortedBy { it.offset }
        north.zipWithNext().forEach { (left, right) ->
            assertTrue(left.offset + left.width <= right.offset + 0.001f)
        }
    }

    @Test
    fun nonFiniteDimensionsAndOpeningValuesAreSafelyNormalized() {
        val result = normalizeOpenings(
            listOf(HouseOpening(wall = "Nord", type = "sconosciuto", offset = Float.NaN, width = Float.POSITIVE_INFINITY, height = Float.NaN)),
            roomWidth = Float.NaN,
            roomDepth = Float.POSITIVE_INFINITY
        )

        assertEquals(1, result.size)
        assertEquals("Finestra", result.single().type)
        assertTrue(result.single().offset.isFinite())
        assertTrue(result.single().width.isFinite())
        assertTrue(result.single().height.isFinite())
        assertTrue(result.single().offset >= 0f)
        assertTrue(result.single().offset + result.single().width <= 5.001f)
    }
}
