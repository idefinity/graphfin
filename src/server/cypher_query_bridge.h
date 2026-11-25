/**
 * Copyright 2022 AntGroup CO., Ltd.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <string>

namespace lgraph {
class Galaxy;
class StateMachine;
}  // namespace lgraph

namespace lgraph_api {
enum class GraphQueryType;
}  // namespace lgraph_api

namespace lgraph {

/**
 * @brief Determine whether a cypher/gql script is read-only.
 *
 * Declaration-only bridge: the heavy cypher headers stay out of the REST
 * translation unit and are included only by cypher_query_bridge.cpp.
 * The returned name/type carry plugin information, as with
 * cypher::Scheduler::DetermineReadOnly.
 */
bool DetermineReadOnlyViaCypher(StateMachine *state_machine, Galaxy *galaxy,
                                const std::string &user, const std::string &graph,
                                const lgraph_api::GraphQueryType &query_type,
                                const std::string &query, std::string &name,
                                std::string &type);

}  // namespace lgraph
