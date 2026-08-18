package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context
import android.util.AttributeSet
import android.view.ViewGroup

/**
 * Lays children out left-to-right, wrapping onto a new line whenever the next
 * child would not fit in the remaining width.
 *
 * The overlay's category chips are text-sized ("Groceries" vs "Health &
 * Beauty"), which a fixed-column GridLayout handles badly: every column is as
 * wide as its widest chip, so the row overflows the card and the trailing
 * column is silently clipped by the card padding. The user then sees a half
 * chip and no way to reach it. Wrapping instead keeps every chip whole and on
 * screen, which matters more than usual here because the card auto-dismisses
 * after a few seconds — an option you cannot see in that window is an option
 * you do not have.
 */
class FlowLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : ViewGroup(context, attrs, defStyleAttr) {

    override fun generateLayoutParams(attrs: AttributeSet?): LayoutParams =
        MarginLayoutParams(context, attrs)

    override fun generateDefaultLayoutParams(): LayoutParams =
        MarginLayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)

    override fun generateLayoutParams(p: LayoutParams?): LayoutParams =
        if (p == null) generateDefaultLayoutParams() else MarginLayoutParams(p)

    override fun checkLayoutParams(p: LayoutParams?): Boolean = p is MarginLayoutParams

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val availableWidth =
            MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight

        var lineWidth = 0
        var lineHeight = 0
        var widestLine = 0
        var totalHeight = 0

        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue

            measureChildWithMargins(child, widthMeasureSpec, 0, heightMeasureSpec, 0)
            val lp = child.layoutParams as MarginLayoutParams
            val childWidth = child.measuredWidth + lp.leftMargin + lp.rightMargin
            val childHeight = child.measuredHeight + lp.topMargin + lp.bottomMargin

            // `lineWidth > 0` keeps a single over-wide child on its own line
            // rather than looping forever trying to find somewhere it fits.
            if (lineWidth + childWidth > availableWidth && lineWidth > 0) {
                widestLine = maxOf(widestLine, lineWidth)
                totalHeight += lineHeight
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += childWidth
            lineHeight = maxOf(lineHeight, childHeight)
        }
        widestLine = maxOf(widestLine, lineWidth)
        totalHeight += lineHeight

        setMeasuredDimension(
            resolveSize(widestLine + paddingLeft + paddingRight, widthMeasureSpec),
            resolveSize(totalHeight + paddingTop + paddingBottom, heightMeasureSpec),
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val availableWidth = right - left - paddingLeft - paddingRight
        var x = paddingLeft
        var y = paddingTop
        var lineHeight = 0

        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == GONE) continue

            val lp = child.layoutParams as MarginLayoutParams
            val childWidth = child.measuredWidth + lp.leftMargin + lp.rightMargin
            val childHeight = child.measuredHeight + lp.topMargin + lp.bottomMargin

            if (x + childWidth > paddingLeft + availableWidth && x > paddingLeft) {
                x = paddingLeft
                y += lineHeight
                lineHeight = 0
            }
            child.layout(
                x + lp.leftMargin,
                y + lp.topMargin,
                x + lp.leftMargin + child.measuredWidth,
                y + lp.topMargin + child.measuredHeight,
            )
            x += childWidth
            lineHeight = maxOf(lineHeight, childHeight)
        }
    }
}
