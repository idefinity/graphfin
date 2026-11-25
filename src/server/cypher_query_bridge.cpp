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

#ifndef _WIN32
#include "cypher/execution_plan/scheduler.h"
#include "execution_plan/runtime_context.h"
#endif

#include "db/galaxy.h"
#include "server/cypher_query_bridge.h"
#include "server/state_machine.h"

namespace lgraph {

#ifndef _WIN32
bool DetermineReadOnlyViaCypher(StateMachine *state_machine, Galaxy *galaxy,
                                const std::string &user, const std::string &graph,
                                const lgraph_api::GraphQueryType &query_type,
                                const std::string &query, std::string &name,
                                std::string &type) {
    cypher::RTContext ctx(state_machine, galaxy, user, graph,
                          state_machine->IsCypherV2());
    return cypher::Scheduler::DetermineReadOnly(&ctx, query_type, query, name,
                                                type);
}
#endif

}  // namespace lgraph
