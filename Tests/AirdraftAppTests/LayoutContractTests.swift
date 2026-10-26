import XCTest

/// Window, sidebar, island, card and navigation metrics that CLAUDE.md and
/// docs/PRODUCT.md fix. A change here is a design decision, not a refactor.
@MainActor
final class LayoutContractTests: XCTestCase {
    /// Window and titlebar, sidebar widths and brand, the content island and the page header blur.
    func testWindowSidebarIslandAndPageHeaderGeometry() {
        XCTAssertEqual(Theme.windowWidth, 784)
        XCTAssertEqual(Theme.windowMinHeight, 600)
        XCTAssertEqual(Theme.titlebarHeight, 46)
        XCTAssertEqual(Theme.windowControlsInset, 16)

        XCTAssertEqual(Theme.sidebarWidth, 180)
        XCTAssertEqual(Theme.sidebarContentInset, 10)
        XCTAssertEqual(Theme.sidebarIconSize, 13)
        // The brand mark is the original compact mark scaled by 1.4: about 57 by 28 points.
        XCTAssertEqual(Theme.sidebarBrandHeight, 28)
        XCTAssertEqual(Theme.sidebarBrandWidth, 744 * 28 / 364, accuracy: 0.0001)
        XCTAssertEqual(Theme.sidebarBrandWidth.rounded(), 57)
        // The collapsed rail is the unchanged brand width plus equal 20-point side insets.
        XCTAssertEqual(Theme.sidebarContentInset + Theme.sidebarBrandInset, 20)
        XCTAssertEqual(Theme.sidebarCollapsedWidth, Theme.sidebarBrandWidth + 40, accuracy: 0.0001)

        XCTAssertEqual(Theme.islandInset, Theme.sidebarContentInset)
        XCTAssertEqual(Theme.islandInset, 10)
        XCTAssertEqual(Theme.islandRadius, 12)

        XCTAssertEqual(Theme.pagePadding, 24)
        // One 60-point sticky header: 16 above a 32-point row, 12 below.
        XCTAssertEqual(Theme.pageHeaderTopInset + Theme.pageHeaderRowHeight + Theme.pageHeaderBottomInset, 60)
        XCTAssertEqual(Theme.pageHeaderRowHeight, 32)
        // The blur extends 20 points below the header, 80 in total, up to a 32-point radius.
        XCTAssertEqual(Theme.pageHeaderBlurExtension, 20)
        XCTAssertEqual(Theme.pageHeaderBlurRadius, 32)
        XCTAssertEqual(Theme.sidebarToggleTop, Theme.islandInset + Theme.pageHeaderTopInset)
    }

    /// Cards and sections, sidebar navigation metrics, and the island following the well 300 ms later.
    func testCardsSectionsNavigationMetricsAndSelectionMotion() {
        XCTAssertEqual(Theme.cardPadding, 16)
        XCTAssertEqual(Theme.cardRadius, 18)
        XCTAssertEqual(Theme.sectionTitleMinHeight, 32)
        XCTAssertEqual(Theme.sectionTitleSpacing, 12)
        XCTAssertEqual(Theme.sectionSpacing, 28)
        XCTAssertEqual(Theme.sectionTitleLeadingInset, 4)
        XCTAssertEqual(Theme.modelTableMaxHeight, 300)

        XCTAssertEqual(NavigationStyle.destinationHeight, 34)
        XCTAssertEqual(NavigationStyle.microphoneHeight, 38)
        XCTAssertEqual(NavigationStyle.destinationInset, 4)
        XCTAssertEqual(NavigationStyle.labelStart, 44)
        XCTAssertEqual(NavigationStyle.wellRadius, 12)
        XCTAssertEqual(NavigationStyle.iconIslandInset, 3)
        // The icon island is 28 points and the microphone socket 32 points, 3 points inside.
        XCTAssertEqual(NavigationStyle.iconIslandSize, 28)
        XCTAssertEqual(NavigationStyle.microphoneSocketSize, 32)
        // Concentric corners: the well's radius less the inset, 9 points.
        XCTAssertEqual(NavigationStyle.iconIslandShape.cornerSize.width, 9)
        XCTAssertEqual(NavigationStyle.wellShape.cornerSize.width, NavigationStyle.wellRadius)

        XCTAssertEqual(SelectionMotion.islandDelay, 0.3, accuracy: 0.0001)
    }
}
