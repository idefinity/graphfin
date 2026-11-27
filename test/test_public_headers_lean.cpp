/**
 * Copyright 2022 AntGroup CO., Ltd.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Opt into lean mode before any project header, then include the same public
// headers as test_public_headers.cpp. unit_test does not define this macro, so
// the opt-in has to come from the translation unit itself to be effective here.
#define LGRAPH_LOG_LEAN

#include "fma-common/timed_task.h"
#include "lgraph/lgraph_spatial.h"
#include "lgraph/olap_on_db.h"
#include "tools/lgraph_log.h"

#include "./ut_utils.h"

TEST(TestPublicHeadersLean, LeanHeadersCompileAndLog) {
    lgraph_api::SRID srid = lgraph_api::SRID::CARTESIAN;
    lgraph_api::Point<lgraph_api::Cartesian> point(1.0, 2.0, srid);
    EXPECT_FALSE(point.AsEWKB().empty());

    // The narrow Boost.Log headers must still cover these facilities when the
    // umbrella headers are opted out. Umbrella-only symbols are intentionally
    // not referenced here (see test_public_headers.cpp for the default mode).
    LOG_INFO() << "lean public header check";
    auto severity = lgraph_log::expr::attr<int>("Severity");
    (void)severity;
    lgraph_log::sinks::text_ostream_backend backend;
    (void)backend;
}
