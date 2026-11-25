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
#include <pplx/threadpool.h>
#endif
#include <exception>

#include "server/rest_service.h"
#include "tools/lgraph_log.h"

namespace lgraph {

#ifndef _WIN32
void InitRestThreadPool(int thread_limit) {
    if (thread_limit == 0) return;
    try {
        crossplat::threadpool::initialize_with_threads(thread_limit);
    } catch (const std::exception &e) {
        LOG_WARN() << "failed to init cpprest threadpool, exception:" << e.what();
    }
}
#endif

}  // namespace lgraph
