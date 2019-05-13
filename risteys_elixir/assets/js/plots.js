import * as d3 from "d3";

var width = 600,
    height = width / 2,
    label_margin = 30,
    margin = {
        top: 0,
        right: 0,
        bottom: 20 + label_margin,
        left: 40 + label_margin,
    },
    isCumulative = false;

let accumulate = (data) => {
    let sum_data = [];
    let sum = 0;
    let has_nan = false;
    for (var item of data) {
        if (isNaN(item.value)) {
            has_nan = true;
        }
        // The following line is specific to ACCumulate
        sum += item.value;
        sum_data.push({name: item.name, value: sum});
    }

    // Switch histogram style only if no NaN-values
    if (has_nan) {
        return data;
    } else {
        return sum_data;
    }
}

let decumulate = (data) => {
    let dec_data = [];
    let prev = 0;
    let has_nan = false;

    for (var item of data) {
        if (isNaN(item.value)) {
            has_nan = true;
        }
        // The 2 following lines are specific to DECumulate
        let current = item.value - prev;
        prev = item.value;
        dec_data.push({name: item.name, value: current});
    }

    // Switch histogram style only if no NaN-values
    if (has_nan) {
        return data;
    } else {
        return dec_data;
    }
}

let makeHistogram = (title, xlabel, ylabel, cumulative, div_name, data) => {
    prepareHistogram(title, xlabel, ylabel, cumulative, div_name, data);
    putData(div_name, data);
}

let prepareHistogram = (title, xlabel, ylabel, cumulative, div_name, data) => {
    let selector = "#" + div_name;
    let id_bins = "#" + div_name + "_rects";

    let svg = d3.select(selector)
        .append("svg")
        .attr("width", width)
        .attr("height", height)
        .attr("class", "font-sans");

    let tooltip = d3.select(selector)
        .append("div")
        .attr("id", div_name + "_tooltip")
        .attr("class", "tooltip")
        .style("display", "none");

    svg.append("g")
        .attr("id", div_name + "_rects")
        .attr("fill", "#2779bd")
        .attr("transform", "translate(0, 300) scale(1, -1)");

    svg.append("g")
        .attr("id", div_name + "_xaxis");

    svg.append("g")
        .attr("id", div_name + "_yaxis");

    // Title
    svg.append("text")
        .attr("transform",
            `translate(${width / 2}, 15)`)
        .attr("class", "font-bold")
        .style("text-anchor", "middle")
        .text(title);

    // X axis label
    svg.append("text")
        .attr("transform",
              `translate(${width / 2}, ${height - 10})`)  // "10" to make the label fully inside the SVG
        .style("text-anchor", "middle")
        .text(xlabel);

    // Y axis label
    svg.append("text")
        .attr("transform", `rotate(-90) translate(${- height / 2}, ${label_margin})`)
        .style("text-anchor", "middle")
        .text(ylabel);

    // Toggle cumulative
    if (cumulative) {
        svg.attr("class", svg.attr("class") + " cumulative");
        svg.on("click", () => {
            isCumulative = !isCumulative;
            let data = svg.select(id_bins).selectAll("rect").data();
            if (isCumulative) {
                putData(div_name, accumulate(data));
            } else {
                putData(div_name, decumulate(data));
            }
        });
    }
};

let putData = (div_name, data) => {
    let id_xaxis = "#" + div_name + "_xaxis";
    let id_yaxis = "#" + div_name + "_yaxis";
    let id_bins = "#" + div_name + "_rects";
    let id_tooltip = "#" + div_name + "_tooltip";

    let x = d3.scaleBand()
        .domain(data.map(d => d.name))
        .range([margin.left, width - margin.right])
        .padding(0.2);

    let y = d3.scaleLinear()
        .domain([0, d3.max(data, d => d.value)]).nice()
        .range([height - margin.bottom, margin.top + 20]);

    let xAxis = (g) => g
        .attr("transform", `translate(0, ${height - margin.bottom})`)
        .call(d3.axisBottom(x).tickSizeOuter(0));

    let yAxis = (g) => g
        .attr("transform", `translate(${margin.left}, 0)`)
        .call(d3.axisLeft(y));

    d3.select(id_xaxis)
        .call(xAxis);

    d3.select(id_yaxis)
        .call(yAxis);

    // TODO could refactor the shared parts of enter and update
    // TODO check error on click in JavaScript console: "Error: unknown type: mouseover"
    d3.select(id_bins)
        .selectAll("rect")
        .data(data)
        .join(
            enter => enter.append("rect")
                        .attr("height", d => {
                            if (isNaN(d.value)) {
                                return y(0)
                            } else {
                                return y(0) - y(d.value)
                            }
                        })
                        .attr("fill", d => {
                            if (isNaN(d.value)) {
                                return "#f1f5f8"
                            } else {
                                return ""
                            }
                        })
                        .on("mouseover", d => {
                            d3.select(id_tooltip)
                                .style("display", "block")
                                .html(d.value)
                                .style("left", d3.event.pageX + "px")
                                .style("top", d3.event.pageY + "px");
                        })
                        .on("mouseout", d => {
                            d3.select(id_tooltip)
                                .style("display", "none");
                        }),
            update => update
                        .call(update => update.transition().duration(100)
                            .attr("height", d => {
                                if (isNaN(d.value)) {
                                    return y(0)
                                } else {
                                    return y(0) - y(d.value)
                                }
                            })
                            .attr("fill", d => {
                                if (isNaN(d.value)) {
                                    return "#f1f5f8"
                                } else {
                                    return ""
                                }
                            })
                            .on("mouseover", d => {
                                d3.select(id_tooltip)
                                    .style("display", "block")
                                    .html(d.value)
                                    .style("left", d3.event.pageX + "px")
                                    .style("top", d3.event.pageY + "px");
                            })
                            .on("mouseout", d => {
                                d3.select(id_tooltip)
                                    .style("display", "none");
                            })
                        ),
        )
        .attr("x", d => x(d.name))
        .attr("y", margin.bottom)
        .attr("width", x.bandwidth());
};

export {makeHistogram};
