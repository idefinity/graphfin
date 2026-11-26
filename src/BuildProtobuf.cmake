# Generate ha.pb.cc/ha.pb.h once and compile ha.pb.cc into a single OBJECT
# library. Every target that needs the generated code links this library, so
# protoc runs once and the generated source is compiled once.
include(cmake/GenerateProtobuf.cmake)
GenerateProtobufCpp(${CMAKE_CURRENT_LIST_DIR}/protobuf
        PROTO_HA_SRCS PROTO_HA_HEADERS
        ${CMAKE_CURRENT_LIST_DIR}/protobuf/ha.proto)

add_library(lgraph_proto_ha OBJECT ${PROTO_HA_SRCS} ${PROTO_HA_HEADERS})
# lgraph, lgraph4jni and lgraph_client_cpp_rpc are SHARED libraries.
set_target_properties(lgraph_proto_ha PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(lgraph_proto_ha PUBLIC ${CMAKE_CURRENT_LIST_DIR}/protobuf)
