set(CLIENT_TEST_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/loot_highlight_test.cpp
)

otclient_add_gtest(otclient_loot_highlight_tests ${CLIENT_TEST_SOURCES})
